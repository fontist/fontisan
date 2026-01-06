# frozen_string_literal: true

require "bindata"
require_relative "constants"
require_relative "collection/shared_logic"

module Fontisan
  # Abstract base class for font collections (TTC/OTC)
  #
  # This class implements the shared logic for TrueTypeCollection and OpenTypeCollection
  # using the Template Method pattern. Subclasses must implement the abstract methods
  # to specify their font class and collection format.
  #
  # The BinData structure definition is shared between both collection types since
  # both TTC and OTC files use the same "ttcf" tag and binary format. The only
  # differences are:
  # 1. The type of fonts contained (TrueType vs OpenType)
  # 2. The format string used for display ("TTC" vs "OTC")
  #
  # @abstract Subclass and override {font_class} and {collection_format}
  #
  # @example Implementing a collection subclass
  #   class TrueTypeCollection < BaseCollection
  #     def self.font_class
  #       TrueTypeFont
  #     end
  #
  #     def self.collection_format
  #       "TTC"
  #     end
  #   end
  class BaseCollection < BinData::Record
    include Collection::SharedLogic

    endian :big

    string :tag, length: 4, assert: "ttcf"
    uint16 :major_version
    uint16 :minor_version
    uint32 :num_fonts
    array :font_offsets, type: :uint32, initial_length: :num_fonts

    # Abstract method: Get the font class for this collection type
    #
    # Subclasses must override this to return their specific font class
    # (TrueTypeFont or OpenTypeFont).
    #
    # @return [Class] The font class (TrueTypeFont or OpenTypeFont)
    # @raise [NotImplementedError] if not overridden by subclass
    def self.font_class
      raise NotImplementedError,
            "#{name} must implement self.font_class"
    end

    # Abstract method: Get the collection format string
    #
    # Subclasses must override this to return "TTC" or "OTC".
    #
    # @return [String] Collection format ("TTC" or "OTC")
    # @raise [NotImplementedError] if not overridden by subclass
    def self.collection_format
      raise NotImplementedError,
            "#{name} must implement self.collection_format"
    end

    # Read collection from a file
    #
    # @param path [String] Path to the collection file
    # @return [BaseCollection] A new instance
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
      raise "Invalid #{collection_format} file: #{e.message}"
    rescue EOFError => e
      raise "Invalid #{collection_format} file: unexpected end of file - #{e.message}"
    end

    # Extract fonts from the collection
    #
    # Reads each font from the collection file and returns them as font objects.
    #
    # @param io [IO] Open file handle to read fonts from
    # @return [Array] Array of font objects (TrueTypeFont or OpenTypeFont)
    def extract_fonts(io)
      font_class = self.class.font_class

      font_offsets.map do |offset|
        font_class.from_collection(io, offset)
      end
    end

    # Get a single font from the collection
    #
    # @param index [Integer] Index of the font (0-based)
    # @param io [IO] Open file handle
    # @param mode [Symbol] Loading mode (:metadata or :full, default: :full)
    # @return [TrueTypeFont, OpenTypeFont, nil] Font object or nil if index out of range
    def font(index, io, mode: LoadingModes::FULL)
      return nil if index >= num_fonts

      font_class = self.class.font_class
      font_class.from_collection(io, font_offsets[index], mode: mode)
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

    # Get the collection version as a single integer
    #
    # @return [Integer] Version number (e.g., 0x00010000 for version 1.0)
    def version
      (major_version << 16) | minor_version
    end

    # Get the collection version as a string
    #
    # @return [String] Version string (e.g., "1.0")
    def version_string
      "#{major_version}.#{minor_version}"
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
    #   File.open("fonts.ttc", "rb") do |io|
    #     collection = TrueTypeCollection.read(io)
    #     list = collection.list_fonts(io)
    #     list.fonts.each { |f| puts "#{f.index}: #{f.family_name}" }
    #   end
    def list_fonts(io)
      require_relative "models/collection_list_info"
      require_relative "models/collection_font_summary"
      require_relative "tables/name"

      font_class = self.class.font_class

      fonts = font_offsets.map.with_index do |offset, index|
        font = font_class.from_collection(io, offset)

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
    #   File.open("fonts.ttc", "rb") do |io|
    #     collection = TrueTypeCollection.read(io)
    #     info = collection.collection_info(io, "fonts.ttc")
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
        collection_format: self.class.collection_format,
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
      font_class = self.class.font_class

      # Extract all fonts
      fonts = font_offsets.map do |offset|
        font_class.from_collection(io, offset)
      end

      # Use shared logic for calculation
      calculate_table_sharing_for_fonts(fonts)
    end
  end
end
