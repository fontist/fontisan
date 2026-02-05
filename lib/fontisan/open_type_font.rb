# frozen_string_literal: true

require_relative "sfnt_font"

module Fontisan
  # OpenType Font domain object
  #
  # Represents an OpenType Font file (CFF outlines). Inherits all shared
  # SFNT functionality from SfntFont and adds OpenType-specific behavior
  # including page-aligned lazy loading for optimal performance.
  #
  # @example Reading and analyzing a font
  #   otf = OpenTypeFont.from_file("font.otf")
  #   puts otf.header.num_tables  # => 12
  #   name_table = otf.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Loading with metadata mode
  #   otf = OpenTypeFont.from_file("font.otf", mode: :metadata)
  #   puts otf.loading_mode  # => :metadata
  #   otf.table_available?("GSUB")  # => false
  #
  # @example Writing a font
  #   otf.to_file("output.otf")
  #
  # @example Reading from TTC collection
  #   otf = OpenTypeFont.from_collection(io, offset)
  class OpenTypeFont < SfntFont
    # Page cache for lazy loading (maps page_start_offset => page_data)
    attr_accessor :page_cache

    # Page size for lazy loading alignment (typical filesystem page size)
    PAGE_SIZE = 4096

    # Initialize storage hashes
    #
    # Extends base class to add page_cache for lazy loading.
    #
    # @return [void]
    def initialize_storage
      super
      @page_cache = {}
    end

    # Validate format correctness
    #
    # Extends base class to check for CFF table (OpenType-specific).
    #
    # @return [Boolean] true if the OTF format is valid, false otherwise
    def valid?
      return false unless super
      return false unless has_table?(Constants::CFF_TAG)

      true
    end

    # Check if font is TrueType flavored
    #
    # @return [Boolean] false for OpenType fonts
    def truetype?
      false
    end

    # Check if font is CFF flavored
    #
    # @return [Boolean] true for OpenType fonts
    def cff?
      true
    end

    private

    # Load a single table's data on demand
    #
    # Uses page-aligned reads and caches pages to ensure lazy loading
    # performance is not slower than eager loading.
    #
    # @param tag [String] The table tag to load
    # @return [void]
    def load_table_data(tag)
      return unless @io_source

      entry = find_table_entry(tag)
      return nil unless entry

      # Use page-aligned reading with caching
      table_start = entry.offset
      table_end = entry.offset + entry.table_length

      # Calculate page boundaries
      page_start = (table_start / PAGE_SIZE) * PAGE_SIZE
      page_end = ((table_end + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE

      # Read all required pages (or use cached pages)
      table_data_parts = []
      current_page = page_start

      while current_page < page_end
        page_data = @page_cache[current_page]

        unless page_data
          # Read page from disk and cache it
          @io_source.seek(current_page)
          page_data = @io_source.read(PAGE_SIZE) || ""
          @page_cache[current_page] = page_data
        end

        # Calculate which part of this page we need
        chunk_start = [table_start - current_page, 0].max
        chunk_end = [table_end - current_page, PAGE_SIZE].min

        if chunk_end > chunk_start
          table_data_parts << page_data[chunk_start...chunk_end]
        end

        current_page += PAGE_SIZE
      end

      # Combine parts and store
      tag_key = tag.dup.force_encoding("UTF-8")
      @table_data[tag_key] = table_data_parts.join
    end

    # Map table tag to parser class
    #
    # OpenType-specific mapping includes CFF table.
    #
    # @param tag [String] The table tag
    # @return [Class, nil] Table parser class or nil
    def table_class_for(tag)
      {
        Constants::HEAD_TAG => Tables::Head,
        Constants::HHEA_TAG => Tables::Hhea,
        Constants::HMTX_TAG => Tables::Hmtx,
        Constants::MAXP_TAG => Tables::Maxp,
        Constants::NAME_TAG => Tables::Name,
        Constants::OS2_TAG => Tables::Os2,
        Constants::POST_TAG => Tables::Post,
        Constants::CMAP_TAG => Tables::Cmap,
        Constants::CFF_TAG => Tables::Cff,
        Constants::FVAR_TAG => Tables::Fvar,
        Constants::GSUB_TAG => Tables::Gsub,
        Constants::GPOS_TAG => Tables::Gpos,
        Constants::GLYF_TAG => Tables::Glyf,
        Constants::LOCA_TAG => Tables::Loca,
        "SVG " => Tables::Svg,
        "COLR" => Tables::Colr,
        "CPAL" => Tables::Cpal,
        "CBDT" => Tables::Cbdt,
        "CBLC" => Tables::Cblc,
        "sbix" => Tables::Sbix,
      }[tag]
    end
  end
end
