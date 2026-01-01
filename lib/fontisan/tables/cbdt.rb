# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # CBDT (Color Bitmap Data) table parser
    #
    # The CBDT table contains the actual bitmap data for color glyphs. It works
    # together with the CBLC table which provides the location information for
    # finding bitmaps in this table.
    #
    # CBDT Table Structure:
    # ```
    # CBDT Table = Header (8 bytes)
    #            + Bitmap Data (variable length)
    # ```
    #
    # Header (8 bytes):
    # - majorVersion (uint16): Major version (2 or 3)
    # - minorVersion (uint16): Minor version (0)
    # - reserved (uint32): Reserved, set to 0
    #
    # The bitmap data format depends on the index subtable format in CBLC.
    # Common formats include:
    # - Format 17: Small metrics, PNG data
    # - Format 18: Big metrics, PNG data
    # - Format 19: Metrics in CBLC, PNG data
    #
    # This parser provides low-level access to bitmap data. For proper bitmap
    # extraction, use together with CBLC table which contains the index.
    #
    # Reference: OpenType CBDT specification
    # https://docs.microsoft.com/en-us/typography/opentype/spec/cbdt
    #
    # @example Reading a CBDT table
    #   data = font.table_data['CBDT']
    #   cbdt = Fontisan::Tables::Cbdt.read(data)
    #   bitmap_data = cbdt.bitmap_data_at(offset, length)
    class Cbdt < Binary::BaseRecord
      # OpenType table tag for CBDT
      TAG = "CBDT"

      # Supported CBDT versions
      VERSION_2_0 = 0x0002_0000
      VERSION_3_0 = 0x0003_0000

      # @return [Integer] Major version (2 or 3)
      attr_reader :major_version

      # @return [Integer] Minor version (0)
      attr_reader :minor_version

      # @return [String] Raw binary data for the entire CBDT table
      attr_reader :raw_data

      # Override read to parse CBDT structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Cbdt] Parsed CBDT table
      def self.read(io)
        cbdt = new
        return cbdt if io.nil?

        data = io.is_a?(String) ? io : io.read
        cbdt.parse!(data)
        cbdt
      end

      # Parse the CBDT table structure
      #
      # @param data [String] Binary data for the CBDT table
      # @raise [CorruptedTableError] If CBDT structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse CBDT header (8 bytes)
        parse_header(io)
        validate_header!
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse CBDT table: #{e.message}"
      end

      # Get bitmap data at specific offset and length
      #
      # Used together with CBLC index to extract bitmap data.
      #
      # @param offset [Integer] Offset from start of table
      # @param length [Integer] Length of bitmap data
      # @return [String, nil] Binary bitmap data or nil
      def bitmap_data_at(offset, length)
        return nil if offset.nil? || length.nil?
        return nil if offset.negative? || length.negative?
        return nil if offset + length > raw_data.length

        raw_data[offset, length]
      end

      # Get combined version number
      #
      # @return [Integer] Combined version (e.g., 0x00020000 for v2.0)
      def version
        return nil if major_version.nil? || minor_version.nil?

        (major_version << 16) | minor_version
      end

      # Get table data size
      #
      # @return [Integer] Size of CBDT table in bytes
      def data_size
        raw_data&.length || 0
      end

      # Check if offset is valid for this table
      #
      # @param offset [Integer] Offset to check
      # @return [Boolean] True if offset is within table bounds
      def valid_offset?(offset)
        return false if offset.nil? || offset.negative?
        return false if raw_data.nil?

        offset < raw_data.length
      end

      # Validate the CBDT table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if major_version.nil? || minor_version.nil?
        return false unless [2, 3].include?(major_version)
        return false unless minor_version.zero?
        return false unless raw_data

        true
      end

      private

      # Parse CBDT header (8 bytes)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @major_version = io.read(2).unpack1("n")
        @minor_version = io.read(2).unpack1("n")
        @reserved = io.read(4).unpack1("N")
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless [2, 3].include?(major_version)
          raise CorruptedTableError,
                "Unsupported CBDT major version: #{major_version} " \
                "(only versions 2 and 3 supported)"
        end

        unless minor_version.zero?
          raise CorruptedTableError,
                "Unsupported CBDT minor version: #{minor_version} " \
                "(only version 0 supported)"
        end
      end
    end
  end
end