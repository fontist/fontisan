# frozen_string_literal: true

require_relative "parsers/dfont_parser"
require_relative "error"
require_relative "collection/shared_logic"

module Fontisan
  # DfontCollection represents an Apple dfont suitcase containing multiple fonts
  #
  # dfont (Data Fork Font) is an Apple-specific format that stores Mac font
  # suitcase resources in the data fork. It can contain multiple SFNT fonts
  # (TrueType or OpenType).
  #
  # This class provides a collection interface similar to TrueTypeCollection
  # and OpenTypeCollection for consistency.
  #
  # @example Load dfont collection
  #   collection = DfontCollection.from_file("family.dfont")
  #   puts "Collection has #{collection.num_fonts} fonts"
  #
  # @example Extract fonts from dfont
  #   File.open("family.dfont", "rb") do |io|
  #     fonts = collection.extract_fonts(io)
  #     fonts.each { |font| puts font.class.name }
  #   end
  class DfontCollection
    include Collection::SharedLogic

    # Path to dfont file
    # @return [String]
    attr_reader :path

    # Number of fonts in collection
    # @return [Integer]
    attr_reader :num_fonts
    alias font_count num_fonts

    # Get font offsets (indices for dfont)
    #
    # dfont doesn't use byte offsets like TTC/OTC, so we return indices
    #
    # @return [Array<Integer>] Array of font indices
    def font_offsets
      (0...@num_fonts).to_a
    end

    # Get the collection format identifier
    #
    # @return [String] "dfont" for dfont collection
    def self.collection_format
      "dfont"
    end

    # Load dfont collection from file
    #
    # @param path [String] Path to dfont file
    # @return [DfontCollection] Collection object
    # @raise [InvalidFontError] if not valid dfont
    def self.from_file(path)
      File.open(path, "rb") do |io|
        unless Parsers::DfontParser.dfont?(io)
          raise InvalidFontError, "Not a valid dfont file: #{path}"
        end

        num_fonts = Parsers::DfontParser.sfnt_count(io)
        new(path, num_fonts)
      end
    end

    # Initialize collection
    #
    # @param path [String] Path to dfont file
    # @param num_fonts [Integer] Number of fonts
    # @api private
    def initialize(path, num_fonts)
      @path = path
      @num_fonts = num_fonts
    end

    # Check if collection is valid
    #
    # @return [Boolean] true if valid
    def valid?
      File.exist?(@path) && @num_fonts.positive?
    end

    # Get the collection version as a string
    #
    # dfont files don't have version numbers like TTC/OTC
    #
    # @return [String] Version string (always "N/A" for dfont)
    def version_string
      "N/A"
    end

    # Extract all fonts from dfont
    #
    # @param io [IO] Open file handle
    # @return [Array<TrueTypeFont, OpenTypeFont>] Array of fonts
    def extract_fonts(io)
      require "stringio"

      fonts = []

      @num_fonts.times do |index|
        io.rewind
        sfnt_data = Parsers::DfontParser.extract_sfnt(io, index: index)

        # Load font from SFNT binary
        sfnt_io = StringIO.new(sfnt_data)
        signature = sfnt_io.read(4)
        sfnt_io.rewind

        # Create font based on signature
        font = case signature
               when [Constants::SFNT_VERSION_TRUETYPE].pack("N"), "true"
                 TrueTypeFont.read(sfnt_io)
               when "OTTO"
                 OpenTypeFont.read(sfnt_io)
               else
                 raise InvalidFontError,
                       "Invalid SFNT signature in dfont at index #{index}: #{signature.inspect}"
               end

        font.initialize_storage
        font.loading_mode = LoadingModes::FULL
        font.lazy_load_enabled = false
        font.read_table_data(sfnt_io)

        fonts << font
      end

      fonts
    end

    # List fonts in collection (brief info)
    #
    # @param io [IO] Open file handle
    # @return [Models::CollectionListInfo] Collection list info
    def list_fonts(io)
      require_relative "models/collection_list_info"
      require_relative "models/collection_font_summary"

      fonts = extract_fonts(io)

      summaries = fonts.map.with_index do |font, index|
        name_table = font.table("name")
        family = name_table.english_name(Models::Tables::Name::FAMILY) || "Unknown"
        subfamily = name_table.english_name(Models::Tables::Name::SUBFAMILY) || "Regular"

        # Detect font format
        format = if font.has_table?("CFF ") || font.has_table?("CFF2")
                   "OpenType"
                 else
                   "TrueType"
                 end

        Models::CollectionFontSummary.new(
          index: index,
          family_name: family,
          subfamily_name: subfamily,
          font_format: format,
        )
      end

      Models::CollectionListInfo.new(
        num_fonts: @num_fonts,
        fonts: summaries,
      )
    end

    # Get specific font from collection
    #
    # @param index [Integer] Font index
    # @param io [IO] Open file handle
    # @param mode [Symbol] Loading mode
    # @return [TrueTypeFont, OpenTypeFont] Font object
    # @raise [InvalidFontError] if index out of range
    def font(index, io, mode: LoadingModes::FULL)
      if index >= @num_fonts
        raise InvalidFontError,
              "Font index #{index} out of range (collection has #{@num_fonts} fonts)"
      end

      io.rewind
      sfnt_data = Parsers::DfontParser.extract_sfnt(io, index: index)

      # Load font from SFNT binary
      require "stringio"
      sfnt_io = StringIO.new(sfnt_data)
      signature = sfnt_io.read(4)
      sfnt_io.rewind

      # Create font based on signature
      font = case signature
             when [Constants::SFNT_VERSION_TRUETYPE].pack("N"), "true"
               TrueTypeFont.read(sfnt_io)
             when "OTTO"
               OpenTypeFont.read(sfnt_io)
             else
               raise InvalidFontError,
                     "Invalid SFNT signature: #{signature.inspect}"
             end

      font.initialize_storage
      font.loading_mode = mode
      font.lazy_load_enabled = false
      font.read_table_data(sfnt_io)

      font
    end

    # Get comprehensive collection metadata
    #
    # Returns a CollectionInfo model with header information and
    # table sharing statistics for the dfont collection.
    # This is the API method used by the `info` command for collections.
    #
    # @param io [IO] Open file handle to read fonts from
    # @param path [String] Collection file path (for file size)
    # @return [Models::CollectionInfo] Collection metadata
    #
    # @example Get collection info
    #   File.open("family.dfont", "rb") do |io|
    #     collection = DfontCollection.from_file("family.dfont")
    #     info = collection.collection_info(io, "family.dfont")
    #     puts "Format: #{info.collection_format}"
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
        ttc_tag: "dfnt", # dfont doesn't use ttcf tag
        major_version: 0, # dfont doesn't have version
        minor_version: 0,
        num_fonts: @num_fonts,
        font_offsets: font_offsets,
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
    # @return [Models::TableSharingInfo] Sharing statistics
    def calculate_table_sharing(io)
      # Extract all fonts
      fonts = extract_fonts(io)

      # Use shared logic for calculation
      calculate_table_sharing_for_fonts(fonts)
    end
  end
end
