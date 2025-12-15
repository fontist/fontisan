# frozen_string_literal: true

require "bindata"
require_relative "constants"

module Fontisan
  # OpenType Collection domain object using BinData
  #
  # Represents a complete OpenType Collection file (OTC) using BinData's declarative
  # DSL for binary structure definition. Parallel to TrueTypeCollection but for OpenType fonts.
  #
  # @example Reading and extracting fonts
  #   File.open("fonts.otc", "rb") do |io|
  #     otc = OpenTypeCollection.read(io)
  #     puts otc.num_fonts  # => 4
  #     fonts = otc.extract_fonts(io)  # => [OpenTypeFont, OpenTypeFont, ...]
  #   end
  class OpenTypeCollection < BinData::Record
    endian :big

    string :tag, length: 4, assert: "ttcf"
    uint16 :major_version
    uint16 :minor_version
    uint32 :num_fonts
    array :font_offsets, type: :uint32, initial_length: :num_fonts

    # Read OpenType Collection from a file
    #
    # @param path [String] Path to the OTC file
    # @return [OpenTypeCollection] A new instance
    # @raise [ArgumentError] if path is nil or empty
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [RuntimeError] if file format is invalid
    def self.from_file(path)
      if path.nil? || path.to_s.empty?
        raise ArgumentError,
              "path cannot be nil or empty"
      end
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") { |io| read(io) }
    rescue BinData::ValidityError => e
      raise "Invalid OTC file: #{e.message}"
    rescue EOFError => e
      raise "Invalid OTC file: unexpected end of file - #{e.message}"
    end

    # Extract fonts as OpenTypeFont objects
    #
    # Reads each font from the OTC file and returns them as OpenTypeFont objects.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [Array<OpenTypeFont>] Array of font objects
    def extract_fonts(io)
      require_relative "open_type_font"

      font_offsets.map do |offset|
        OpenTypeFont.from_collection(io, offset)
      end
    end

    # Get a single font from the collection
    #
    # @param index [Integer] Index of the font (0-based)
    # @param io [IO] Open file handle
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [OpenTypeFont, nil] Font object or nil if index out of range
    def font(index, io, mode: LoadingModes::FULL)
      return nil if index >= num_fonts

      require_relative "open_type_font"
      OpenTypeFont.from_collection(io, font_offsets[index], mode: mode)
    end

    # Get font count
    #
    # @return [Integer] Number of fonts in collection
    def font_count
      num_fonts
    end

    # Validate format correctness
    #
    # @return [Boolean] true if the format is valid, false otherwise
    def valid?
      tag == Constants::TTC_TAG && num_fonts.positive? && font_offsets.length == num_fonts
    rescue StandardError
      false
    end

    # Get the OTC version as a single integer
    #
    # @return [Integer] Version number (e.g., 0x00010000 for version 1.0)
    def version
      (major_version << 16) | minor_version
    end

    # List all fonts in the collection with basic metadata
    #
    # Returns a CollectionListInfo model containing summaries of all fonts.
    # This is the API method used by the `ls` command for collections.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [CollectionListInfo] List of fonts with metadata
    #
    # @example List fonts in collection
    #   File.open("fonts.otc", "rb") do |io|
    #     otc = OpenTypeCollection.read(io)
    #     list = otc.list_fonts(io)
    #     list.fonts.each { |f| puts "#{f.index}: #{f.family_name}" }
    #   end
    def list_fonts(io)
      require_relative "models/collection_list_info"
      require_relative "models/collection_font_summary"
      require_relative "open_type_font"
      require_relative "tables/name"

      fonts = font_offsets.map.with_index do |offset, index|
        font = OpenTypeFont.from_collection(io, offset)

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

    # Get comprehensive collection metadata
    #
    # Returns a CollectionInfo model with header information, offsets,
    # and table sharing statistics.
    # This is the API method used by the `info` command for collections.
    #
    # @param io [IO] Open file handle to read fonts from
    # @param path [String] Collection file path (for file size)
    # @return [CollectionInfo] Collection metadata
    #
    # @example Get collection info
    #   File.open("fonts.otc", "rb") do |io|
    #     otc = OpenTypeCollection.read(io)
    #     info = otc.collection_info(io, "fonts.otc")
    #     puts "Version: #{info.version_string}"
    #   end
    def collection_info(io, path)
      require_relative "models/collection_info"
      require_relative "models/table_sharing_info"

      # Calculate table sharing statistics
      table_sharing = calculate_table_sharing(io)

      # Get file size
      file_size = path ? File.size(path) : 0

      Models::CollectionInfo.new(
        collection_path: path,
        collection_format: "OTC",
        ttc_tag: tag,
        major_version: major_version,
        minor_version: minor_version,
        num_fonts: num_fonts,
        font_offsets: font_offsets.to_a,
        file_size_bytes: file_size,
        table_sharing: table_sharing,
      )
    end

    private

    # Calculate table sharing statistics
    #
    # Analyzes which tables are shared between fonts and calculates
    # space savings from deduplication.
    #
    # @param io [IO] Open file handle
    # @return [TableSharingInfo] Sharing statistics
    def calculate_table_sharing(io)
      require_relative "models/table_sharing_info"
      require_relative "open_type_font"

      # Extract all fonts
      fonts = font_offsets.map do |offset|
        OpenTypeFont.from_collection(io, offset)
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
