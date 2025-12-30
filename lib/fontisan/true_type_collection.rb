# frozen_string_literal: true

require_relative "base_collection"

module Fontisan
  # TrueType Collection domain object
  #
  # Represents a complete TrueType Collection file. Inherits all shared
  # functionality from BaseCollection and implements TTC-specific behavior.
  #
  # @example Reading and extracting fonts
  #   File.open("Helvetica.ttc", "rb") do |io|
  #     ttc = TrueTypeCollection.read(io)
  #     puts ttc.num_fonts  # => 6
  #     fonts = ttc.extract_fonts(io)  # => [TrueTypeFont, TrueTypeFont, ...]
  #   end
  class TrueTypeCollection < BaseCollection
    # Get the font class for TrueType collections
    #
    # @return [Class] TrueTypeFont class
    def self.font_class
      require_relative "true_type_font"
      TrueTypeFont
    end

    # Get the collection format identifier
    #
    # @return [String] "TTC" for TrueType Collection
    def self.collection_format
      "TTC"
    end

    # Get a single font from the collection
    #
    # Overrides BaseCollection to use TrueType-specific from_ttc method.
    #
    # @param index [Integer] Index of the font (0-based)
    # @param io [IO] Open file handle
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [TrueTypeFont, nil] Font object or nil if index out of range
    def font(index, io, mode: LoadingModes::FULL)
      return nil if index >= num_fonts

      require_relative "true_type_font"
      TrueTypeFont.from_ttc(io, font_offsets[index], mode: mode)
    end

    # Extract fonts as TrueTypeFont objects
    #
    # Reads each font from the TTC file and returns them as TrueTypeFont objects.
    # This method uses the TTC-specific from_ttc method.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [Array<TrueTypeFont>] Array of font objects
    def extract_fonts(io)
      require_relative "true_type_font"

      font_offsets.map do |offset|
        TrueTypeFont.from_ttc(io, offset)
      end
    end

    # List all fonts in the collection with basic metadata
    #
    # Overrides BaseCollection to use TrueType-specific from_ttc method.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [CollectionListInfo] List of fonts with metadata
    def list_fonts(io)
      require_relative "models/collection_list_info"
      require_relative "models/collection_font_summary"
      require_relative "true_type_font"
      require_relative "tables/name"

      fonts = font_offsets.map.with_index do |offset, index|
        font = TrueTypeFont.from_ttc(io, offset)

        # Extract basic font info
        name_table = font.table("name")
        post_table = font.table("post")

        family_name = name_table&.english_name(Tables::Name::FAMILY) || "Unknown"
        subfamily_name = name_table&.english_name(Tables::Name::SUBFAMILY) || "Regular"
        postscript_name = name_table&.english_name(Tables::Name::POSTSCRIPT_NAME) || "Unknown"

        # Determine font format
        sfnt = font.header.sfnt_version
        font_format = case sfnt
                      when 0x00010000, 0x74727565 # 0x74727565 = 'true'
                        "TrueType"
                      when 0x4F54544F # 'OTTO'
                        "OpenType"
                      else
                        "Unknown"
                      end

        num_glyphs = post_table&.glyph_names&.length || 0
        num_tables = font.table_names.length

        Models::CollectionFontSummary.new(
          index: index,
          family_name: family_name,
          subfamily_name: subfamily_name,
          postscript_name: postscript_name,
          font_format: font_format,
          num_glyphs: num_glyphs,
          num_tables: num_tables,
        )
      end

      Models::CollectionListInfo.new(
        collection_path: nil, # Will be set by command
        num_fonts: num_fonts,
        fonts: fonts,
      )
    end

    private

    # Calculate table sharing statistics
    #
    # Overrides BaseCollection to use TrueType-specific from_ttc method.
    #
    # @param io [IO] Open file handle
    # @return [TableSharingInfo] Sharing statistics
    def calculate_table_sharing(io)
      require_relative "models/table_sharing_info"
      require_relative "true_type_font"

      # Extract all fonts
      fonts = font_offsets.map do |offset|
        TrueTypeFont.from_ttc(io, offset)
      end

      # Build table hash map (checksum -> size)
      table_map = {}
      total_table_size = 0

      fonts.each do |font|
        font.tables.each do |entry|
          key = entry.checksum
          size = entry.table_length
          table_map[key] ||= size
          total_table_size += size
        end
      end

      # Count unique vs shared
      unique_tables = table_map.size
      total_tables = fonts.sum { |f| f.tables.length }
      shared_tables = total_tables - unique_tables

      # Calculate space saved
      unique_size = table_map.values.sum
      space_saved = total_table_size - unique_size

      # Calculate sharing percentage
      sharing_pct = total_tables.positive? ? (shared_tables.to_f / total_tables * 100).round(2) : 0.0

      Models::TableSharingInfo.new(
        shared_tables: shared_tables,
        unique_tables: unique_tables,
        sharing_percentage: sharing_pct,
        space_saved_bytes: space_saved,
      )
    end
  end
end
