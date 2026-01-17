# frozen_string_literal: true

require_relative "sfnt_font"

module Fontisan
  # TrueType Font domain object
  #
  # Represents a TrueType Font file (glyf outlines). Inherits all shared
  # SFNT functionality from SfntFont and adds TrueType-specific behavior.
  #
  # @example Reading and analyzing a font
  #   ttf = TrueTypeFont.from_file("font.ttf")
  #   puts ttf.header.num_tables  # => 14
  #   name_table = ttf.table("name")
  #   puts name_table.english_name(Tables::Name::FAMILY)
  #
  # @example Loading with metadata mode
  #   ttf = TrueTypeFont.from_file("font.ttf", mode: :metadata)
  #   puts ttf.loading_mode  # => :metadata
  #   ttf.table_available?("GSUB")  # => false
  #
  # @example Writing a font
  #   ttf.to_file("output.ttf")
  #
  # @example Reading from TTC collection
  #   ttf = TrueTypeFont.from_ttc(io, offset)
  class TrueTypeFont < SfntFont
    # Read TrueType Font from a file
    #
    # @param path [String] Path to the TTF file
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @param lazy [Boolean] If true, load tables on demand (default: false)
    # @return [TrueTypeFont] A new instance
    # @raise [ArgumentError] if path is nil or empty, or if mode is invalid
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [RuntimeError] if file format is invalid
    def self.from_file(path, mode: LoadingModes::FULL, lazy: false)
      if path.nil? || path.to_s.empty?
        raise ArgumentError,
              "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      # Validate mode
      LoadingModes.validate_mode!(mode)

      File.open(path, "rb") do |io|
        font = read(io)
        font.initialize_storage
        font.loading_mode = mode
        font.lazy_load_enabled = lazy

        if lazy
          # Reuse existing IO handle by duplicating it to prevent double file open
          # The dup ensures the handle stays open after this block closes
          font.io_source = io.dup
          font.setup_finalizer
        else
          # Read tables upfront
          font.read_table_data(io)
        end

        font
      end
    rescue BinData::ValidityError, EOFError => e
      raise "Invalid TTF file: #{e.message}"
    end

    # Read TrueType Font from TTC at specific offset
    #
    # @param io [IO] Open file handle
    # @param offset [Integer] Byte offset to the font
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [TrueTypeFont] A new instance
    def self.from_ttc(io, offset, mode: LoadingModes::FULL)
      LoadingModes.validate_mode!(mode)

      io.seek(offset)
      font = read(io)
      font.initialize_storage
      font.loading_mode = mode
      font.read_table_data(io)
      font
    end

    # Check if font is TrueType flavored
    #
    # @return [Boolean] true for TrueType fonts
    def truetype?
      true
    end

    # Check if font is CFF flavored
    #
    # @return [Boolean] false for TrueType fonts
    def cff?
      false
    end

    private

    # Map table tag to parser class
    #
    # TrueType-specific mapping includes glyf/loca tables.
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
