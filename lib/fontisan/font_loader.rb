# frozen_string_literal: true

require_relative "constants"
require_relative "loading_modes"
require_relative "true_type_font"
require_relative "open_type_font"
require_relative "true_type_collection"
require_relative "open_type_collection"
require_relative "woff_font"
require_relative "woff2_font"
require_relative "error"

module Fontisan
  # FontLoader provides unified font loading with automatic format detection.
  #
  # This class is the primary entry point for loading fonts in Fontisan.
  # It automatically detects the font format and returns the appropriate
  # domain object (TrueTypeFont, OpenTypeFont, TrueTypeCollection, or OpenTypeCollection).
  #
  # @example Load any font type
  #   font = FontLoader.load("font.ttf")  # => TrueTypeFont
  #   font = FontLoader.load("font.otf")  # => OpenTypeFont
  #   font = FontLoader.load("fonts.ttc") # => TrueTypeFont (first in collection)
  #   font = FontLoader.load("fonts.ttc", font_index: 2) # => TrueTypeFont (third in collection)
  #
  # @example Loading modes
  #   font = FontLoader.load("font.ttf", mode: :metadata)  # Load only metadata tables
  #   font = FontLoader.load("font.ttf", mode: :full)      # Load all tables
  #
  # @example Lazy loading control
  #   font = FontLoader.load("font.ttf", lazy: true)   # Tables loaded on-demand
  #   font = FontLoader.load("font.ttf", lazy: false)  # All tables loaded upfront
  class FontLoader
    # Load a font from file with automatic format detection
    #
    # @param path [String] Path to the font file
    # @param font_index [Integer] Index of font in collection (0-based, default: 0)
    # @param mode [Symbol] Loading mode (:metadata or :full, default: from ENV or :full)
    # @param lazy [Boolean] If true, load tables on demand (default: false for eager loading)
    # @return [TrueTypeFont, OpenTypeFont, WoffFont, Woff2Font] The loaded font object
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [UnsupportedFormatError] for unsupported formats
    # @raise [InvalidFontError] for corrupted or unknown formats
    def self.load(path, font_index: 0, mode: nil, lazy: nil)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      # Resolve mode and lazy parameters with environment variables
      resolved_mode = mode || env_mode || LoadingModes::FULL
      resolved_lazy = if lazy.nil?
                        env_lazy.nil? ? false : env_lazy
                      else
                        lazy
                      end

      # Validate mode
      LoadingModes.validate_mode!(resolved_mode)

      File.open(path, "rb") do |io|
        signature = io.read(4)
        io.rewind

        case signature
        when Constants::TTC_TAG
          load_from_collection(io, path, font_index, mode: resolved_mode,
                                                     lazy: resolved_lazy)
        when pack_uint32(Constants::SFNT_VERSION_TRUETYPE), "true"
          TrueTypeFont.from_file(path, mode: resolved_mode, lazy: resolved_lazy)
        when "OTTO"
          OpenTypeFont.from_file(path, mode: resolved_mode, lazy: resolved_lazy)
        when "wOFF"
          WoffFont.from_file(path, mode: resolved_mode, lazy: resolved_lazy)
        when "wOF2"
          Woff2Font.from_file(path, mode: resolved_mode, lazy: resolved_lazy)
        when Constants::DFONT_RESOURCE_HEADER
          extract_and_load_dfont(io, path, font_index, resolved_mode, resolved_lazy)
        else
          raise InvalidFontError,
                "Unknown font format. Expected TTF, OTF, TTC, OTC, WOFF, or WOFF2 file."
        end
      end
    end

    # Check if a file is a collection (TTC or OTC)
    #
    # @param path [String] Path to the font file
    # @return [Boolean] true if file is a TTC/OTC collection
    # @raise [Errno::ENOENT] if file does not exist
    #
    # @example Check if file is collection
    #   FontLoader.collection?("fonts.ttc") # => true
    #   FontLoader.collection?("font.ttf")  # => false
    def self.collection?(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        signature = io.read(4)
        io.rewind

        # Check for TTC/OTC signature
        return true if signature == Constants::TTC_TAG

        # Check for multi-font dfont (suitcase) - only if it's actually a dfont
        if signature == Constants::DFONT_RESOURCE_HEADER
          require_relative "parsers/dfont_parser"
          # Verify it's a valid dfont and has multiple fonts
          return Parsers::DfontParser.dfont?(io) && Parsers::DfontParser.sfnt_count(io) > 1
        end

        false
      end
    end

    # Load a collection object without extracting fonts
    #
    # Returns the collection object (TrueTypeCollection, OpenTypeCollection, or DfontCollection)
    # without extracting individual fonts. Useful for inspecting collection
    # metadata and structure.
    #
    # = Collection Format Understanding
    #
    # Both TTC (TrueType Collection) and OTC (OpenType Collection) files use
    # the same "ttcf" signature. The distinction between TTC and OTC is NOT
    # in the collection format itself, but in the fonts contained within:
    #
    # - TTC typically contains TrueType fonts (glyf outlines)
    # - OTC typically contains OpenType fonts (CFF/CFF2 outlines)
    # - Mixed collections are possible (both TTF and OTF in same collection)
    #
    # dfont (Data Fork Font) is an Apple-specific format that contains Mac
    # font suitcase resources. It can contain multiple SFNT fonts (TrueType
    # or OpenType).
    #
    # Each collection can contain multiple SFNT-format font files, with table
    # deduplication to save space. Individual fonts within a collection are
    # stored at different offsets within the file, each with their own table
    # directory and data tables.
    #
    # = Detection Strategy
    #
    # This method scans ALL fonts in the collection to determine the collection
    # type accurately:
    #
    # 1. Reads all font offsets from the collection header
    # 2. Examines the sfnt_version of each font in the collection
    # 3. Counts TrueType fonts (0x00010000 or 0x74727565 "true") vs OpenType fonts (0x4F54544F "OTTO")
    # 4. If ANY font is OpenType (CFF), returns OpenTypeCollection
    # 5. Only returns TrueTypeCollection if ALL fonts are TrueType
    #
    # For dfont files, returns DfontCollection.
    #
    # This approach correctly handles:
    # - Homogeneous collections (all TTF or all OTF)
    # - Mixed collections (both TTF and OTF fonts) - uses OpenTypeCollection
    # - Large collections with many fonts (like NotoSerifCJK.ttc with 35 fonts)
    # - dfont suitcases (Apple-specific)
    #
    # @param path [String] Path to the collection file
    # @return [TrueTypeCollection, OpenTypeCollection, DfontCollection] The collection object
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [InvalidFontError] if file is not a collection or type cannot be determined
    #
    # @example Load collection for inspection
    #   collection = FontLoader.load_collection("fonts.ttc")
    #   puts "Collection has #{collection.num_fonts} fonts"
    def self.load_collection(path)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        signature = io.read(4)
        io.rewind

        # Check for dfont
        if signature == Constants::DFONT_RESOURCE_HEADER || dfont_signature?(io)
          require_relative "dfont_collection"
          return DfontCollection.from_file(path)
        end

        # Check for TTC/OTC
        unless signature == Constants::TTC_TAG
          raise InvalidFontError,
                "File is not a collection (TTC/OTC/dfont). Use FontLoader.load instead."
        end

        # Read version and num_fonts
        io.seek(8) # Skip tag (4) + version (4)
        num_fonts = io.read(4).unpack1("N")

        # Read all font offsets
        font_offsets = num_fonts.times.map { io.read(4).unpack1("N") }

        # Scan all fonts to determine collection type (not just first)
        truetype_count = 0
        opentype_count = 0

        font_offsets.each do |offset|
          io.rewind
          io.seek(offset)
          sfnt_version = io.read(4).unpack1("N")

          case sfnt_version
          when Constants::SFNT_VERSION_TRUETYPE, 0x74727565 # 0x74727565 = 'true'
            truetype_count += 1
          when Constants::SFNT_VERSION_OTTO
            opentype_count += 1
          else
            raise InvalidFontError,
                  "Unknown font type in collection at offset #{offset} (sfnt version: 0x#{sfnt_version.to_s(16)})"
          end
        end

        io.rewind

        # Determine collection type based on what fonts are inside
        # If ANY font is OpenType, use OpenTypeCollection (more general format)
        # Only use TrueTypeCollection if ALL fonts are TrueType
        if opentype_count > 0
          OpenTypeCollection.from_file(path)
        else
          # All fonts are TrueType
          TrueTypeCollection.from_file(path)
        end
      end
    end

    # Get mode from environment variable
    #
    # @return [Symbol, nil] Mode from FONTISAN_MODE or nil
    # @api private
    def self.env_mode
      env_value = ENV["FONTISAN_MODE"]
      return nil unless env_value

      mode = env_value.to_sym
      LoadingModes.valid_mode?(mode) ? mode : nil
    end

    # Get lazy setting from environment variable
    #
    # @return [Boolean, nil] Lazy setting from FONTISAN_LAZY or nil if not set
    # @api private
    def self.env_lazy
      env_value = ENV["FONTISAN_LAZY"]
      return nil unless env_value

      env_value.downcase == "true"
    end

    # Load from a collection file (TTC or OTC)
    #
    # This is the internal method that handles loading individual fonts from
    # collection files. It reads the collection header to determine the type
    # (TTC vs OTC) and extracts the requested font.
    #
    # = Collection Header Structure
    #
    # TTC/OTC files start with:
    # - Bytes 0-3: "ttcf" tag (4 bytes)
    # - Bytes 4-7: version (2 bytes major + 2 bytes minor)
    # - Bytes 8-11: num_fonts (4 bytes, big-endian uint32)
    # - Bytes 12+: font offset array (4 bytes per font, big-endian uint32)
    #
    # CRITICAL: The method seeks to position 8 (after tag and version) to read
    # num_fonts, NOT position 12 which is where the offset array starts. This
    # was a bug that caused "Unknown font type" errors when the first offset
    # was misread as num_fonts.
    #
    # @param io [IO] Open file handle
    # @param path [String] Path to the collection file
    # @param font_index [Integer] Index of font to extract
    # @param mode [Symbol] Loading mode (:metadata or :full)
    # @param lazy [Boolean] If true, load tables on demand
    # @return [TrueTypeFont, OpenTypeFont] The loaded font object
    # @raise [InvalidFontError] if collection type cannot be determined
    def self.load_from_collection(io, path, font_index,
mode: LoadingModes::FULL, lazy: true)
      # Read collection header to get font offsets
      io.seek(8) # Skip tag (4) + version (4)
      num_fonts = io.read(4).unpack1("N")

      if font_index >= num_fonts
        raise InvalidFontError,
              "Font index #{font_index} out of range (collection has #{num_fonts} fonts)"
      end

      # Read all font offsets
      font_offsets = num_fonts.times.map { io.read(4).unpack1("N") }

      # Scan all fonts to determine collection type (not just first)
      truetype_count = 0
      opentype_count = 0

      font_offsets.each do |offset|
        io.rewind
        io.seek(offset)
        sfnt_version = io.read(4).unpack1("N")

        case sfnt_version
        when Constants::SFNT_VERSION_TRUETYPE, 0x74727565 # 0x74727565 = 'true'
          truetype_count += 1
        when Constants::SFNT_VERSION_OTTO
          opentype_count += 1
        else
          raise InvalidFontError,
                "Unknown font type in collection at offset #{offset} (sfnt version: 0x#{sfnt_version.to_s(16)})"
        end
      end

      io.rewind

      # If ANY font is OpenType, use OpenTypeCollection (more general format)
      # Only use TrueTypeCollection if ALL fonts are TrueType
      if opentype_count > 0
        # OpenType Collection
        otc = OpenTypeCollection.from_file(path)
        File.open(path, "rb") { |f| otc.font(font_index, f, mode: mode) }
      else
        # TrueType Collection (all fonts are TrueType)
        ttc = TrueTypeCollection.from_file(path)
        File.open(path, "rb") { |f| ttc.font(font_index, f, mode: mode) }
      end
    end

    # Extract and load font from dfont resource fork
    #
    # @param io [IO] Open file handle
    # @param path [String] Path to dfont file
    # @param font_index [Integer] Font index in suitcase
    # @param mode [Symbol] Loading mode
    # @param lazy [Boolean] Lazy loading flag
    # @return [TrueTypeFont, OpenTypeFont] Loaded font
    # @api private
    def self.extract_and_load_dfont(io, path, font_index, mode, lazy)
      require_relative "parsers/dfont_parser"

      # Extract SFNT data from resource fork
      sfnt_data = Parsers::DfontParser.extract_sfnt(io, index: font_index)

      # Create StringIO with SFNT data
      sfnt_io = StringIO.new(sfnt_data)

      # Detect SFNT signature
      signature = sfnt_io.read(4)
      sfnt_io.rewind

      # Read and setup font based on signature
      case signature
      when pack_uint32(Constants::SFNT_VERSION_TRUETYPE), "true"
        font = TrueTypeFont.read(sfnt_io)
        font.initialize_storage
        font.loading_mode = mode
        font.lazy_load_enabled = lazy
        font.read_table_data(sfnt_io) unless lazy
        font
      when "OTTO"
        font = OpenTypeFont.read(sfnt_io)
        font.initialize_storage
        font.loading_mode = mode
        font.lazy_load_enabled = lazy
        font.read_table_data(sfnt_io) unless lazy
        font
      else
        raise InvalidFontError,
              "Invalid SFNT data in dfont resource (signature: #{signature.inspect})"
      end
    end

    # Pack uint32 value to big-endian bytes
    #
    # @param value [Integer] The uint32 value
    # @return [String] 4-byte binary string
    # @api private
    def self.pack_uint32(value)
      [value].pack("N")
    end

    private_class_method :load_from_collection, :pack_uint32, :env_mode,
                         :env_lazy, :extract_and_load_dfont

    # Check if file has dfont signature
    #
    # @param io [IO] Open file handle
    # @return [Boolean] true if dfont
    # @api private
    def self.dfont_signature?(io)
      require_relative "parsers/dfont_parser"
      Parsers::DfontParser.dfont?(io)
    end

    private_class_method :dfont_signature?
  end
end
