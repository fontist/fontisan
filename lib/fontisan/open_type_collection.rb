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
    # @return [OpenTypeFont, nil] Font object or nil if index out of range
    def font(index, io)
      return nil if index >= num_fonts

      require_relative "open_type_font"
      OpenTypeFont.from_collection(io, font_offsets[index])
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
  end
end
