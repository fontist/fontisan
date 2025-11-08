# frozen_string_literal: true

require_relative "constants"
require_relative "true_type_font"
require_relative "open_type_font"
require_relative "true_type_collection"
require_relative "open_type_collection"
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
  class FontLoader
    # Load a font from file with automatic format detection
    #
    # @param path [String] Path to the font file
    # @param font_index [Integer] Index of font in collection (0-based, default: 0)
    # @return [TrueTypeFont, OpenTypeFont] The loaded font object
    # @raise [Errno::ENOENT] if file does not exist
    # @raise [UnsupportedFormatError] for WOFF/WOFF2 or other unsupported formats
    # @raise [InvalidFontError] for corrupted or unknown formats
    def self.load(path, font_index: 0)
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)

      File.open(path, "rb") do |io|
        signature = io.read(4)
        io.rewind

        case signature
        when Constants::TTC_TAG
          load_from_collection(io, path, font_index)
        when pack_uint32(Constants::SFNT_VERSION_TRUETYPE)
          TrueTypeFont.from_file(path)
        when "OTTO"
          OpenTypeFont.from_file(path)
        when "wOFF"
          raise UnsupportedFormatError,
                "Unsupported font format: WOFF. Fontisan currently supports TTF, OTF, TTC, and OTC files."
        when "wOF2"
          raise UnsupportedFormatError,
                "Unsupported font format: WOFF2. Fontisan currently supports TTF, OTF, TTC, and OTC files."
        else
          raise InvalidFontError,
                "Unknown font format. Expected TTF, OTF, TTC, or OTC file."
        end
      end
    end

    # Load from a collection file (TTC or OTC)
    #
    # @param io [IO] Open file handle
    # @param path [String] Path to the collection file
    # @param font_index [Integer] Index of font to extract
    # @return [TrueTypeFont, OpenTypeFont] The loaded font object
    # @raise [InvalidFontError] if collection type cannot be determined
    def self.load_from_collection(io, path, font_index)
      # Read collection header to get font offsets
      io.seek(12) # Skip tag (4) + major_version (2) + minor_version (2) + num_fonts marker (4)
      num_fonts = io.read(4).unpack1("N")

      if font_index >= num_fonts
        raise InvalidFontError,
              "Font index #{font_index} out of range (collection has #{num_fonts} fonts)"
      end

      # Read first offset to detect collection type
      first_offset = io.read(4).unpack1("N")

      # Peek at first font's sfnt_version to determine TTC vs OTC
      io.seek(first_offset)
      sfnt_version = io.read(4).unpack1("N")
      io.rewind

      case sfnt_version
      when Constants::SFNT_VERSION_TRUETYPE
        # TrueType Collection
        ttc = TrueTypeCollection.from_file(path)
        File.open(path, "rb") { |f| ttc.font(font_index, f) }
      when Constants::SFNT_VERSION_OTTO
        # OpenType Collection
        otc = OpenTypeCollection.from_file(path)
        File.open(path, "rb") { |f| otc.font(font_index, f) }
      else
        raise InvalidFontError,
              "Unknown font type in collection (sfnt version: 0x#{sfnt_version.to_s(16)})"
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

    private_class_method :load_from_collection, :pack_uint32
  end
end
