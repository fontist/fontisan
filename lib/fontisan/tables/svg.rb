# frozen_string_literal: true

require "stringio"
require "zlib"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # SVG (Scalable Vector Graphics) table parser
    #
    # The SVG table contains embedded SVG documents for glyphs, typically used
    # for color emoji or graphic elements. Each document can cover a range of
    # glyph IDs and may be compressed with gzip.
    #
    # SVG Table Structure:
    # ```
    # SVG Table = Header (10 bytes)
    #           + Document Index
    #           + SVG Documents
    # ```
    #
    # Header (10 bytes):
    # - version (uint16): Table version (0)
    # - svgDocumentListOffset (uint32): Offset to SVG Document Index
    # - reserved (uint32): Reserved, set to 0
    #
    # Document Index:
    # - numEntries (uint16): Number of SVG Document Index Entries
    # - entries[numEntries]: Array of SVG Document Index Entries
    #
    # SVG Document Index Entry (12 bytes):
    # - startGlyphID (uint16): First glyph ID
    # - endGlyphID (uint16): Last glyph ID (inclusive)
    # - svgDocOffset (uint32): Offset to SVG document
    # - svgDocLength (uint32): Length of SVG document
    #
    # SVG documents may be compressed with gzip (identified by magic bytes 0x1f 0x8b).
    #
    # Reference: OpenType SVG specification
    # https://docs.microsoft.com/en-us/typography/opentype/spec/svg
    #
    # @example Reading an SVG table
    #   data = font.table_data['SVG ']
    #   svg = Fontisan::Tables::Svg.read(data)
    #   svg_content = svg.svg_for_glyph(42)
    #   puts "Glyph 42 SVG: #{svg_content}"
    class Svg < Binary::BaseRecord
      # OpenType table tag for SVG (note: includes trailing space)
      TAG = "SVG "

      # SVG Document Index Entry structure
      #
      # Each entry associates a glyph range with an SVG document.
      # Structure (12 bytes): start_glyph_id, end_glyph_id, svg_doc_offset, svg_doc_length
      class SvgDocumentRecord < Binary::BaseRecord
        endian :big
        uint16 :start_glyph_id
        uint16 :end_glyph_id
        uint32 :svg_doc_offset
        uint32 :svg_doc_length

        # Check if this record includes a specific glyph ID
        #
        # @param glyph_id [Integer] Glyph ID to check
        # @return [Boolean] True if glyph is in range
        def includes_glyph?(glyph_id)
          glyph_id >= start_glyph_id && glyph_id <= end_glyph_id
        end

        # Get the glyph range for this record
        #
        # @return [Range] Range of glyph IDs
        def glyph_range
          start_glyph_id..end_glyph_id
        end
      end

      # @return [Integer] SVG table version (0)
      attr_reader :version

      # @return [Integer] Offset to SVG Document Index
      attr_reader :svg_document_list_offset

      # @return [Integer] Number of SVG document entries
      attr_reader :num_entries

      # @return [Array<SvgDocumentRecord>] Parsed document records
      attr_reader :document_records

      # @return [String] Raw binary data for the entire SVG table
      attr_reader :raw_data

      # Override read to parse SVG structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Svg] Parsed SVG table
      def self.read(io)
        svg = new
        return svg if io.nil?

        data = io.is_a?(String) ? io : io.read
        svg.parse!(data)
        svg
      end

      # Parse the SVG table structure
      #
      # @param data [String] Binary data for the SVG table
      # @raise [CorruptedTableError] If SVG structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse SVG header (10 bytes)
        parse_header(io)
        validate_header!

        # Parse document index
        parse_document_index(io)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse SVG table: #{e.message}"
      end

      # Get SVG document for a specific glyph ID
      #
      # Returns the SVG XML content for the specified glyph.
      # Automatically decompresses gzipped content.
      # Returns nil if glyph has no SVG data.
      #
      # @param glyph_id [Integer] Glyph ID to look up
      # @return [String, nil] SVG XML content or nil
      def svg_for_glyph(glyph_id)
        record = find_document_record(glyph_id)
        return nil unless record

        extract_svg_document(record)
      end

      # Check if glyph has SVG data
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph has SVG
      def has_svg_for_glyph?(glyph_id)
        !find_document_record(glyph_id).nil?
      end

      # Get all glyph IDs that have SVG data
      #
      # @return [Array<Integer>] Array of glyph IDs with SVG
      def glyph_ids_with_svg
        document_records.flat_map do |record|
          record.glyph_range.to_a
        end
      end

      # Get the number of SVG documents in this table
      #
      # @return [Integer] Number of SVG documents
      def num_svg_documents
        num_entries
      end

      # Validate the SVG table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if version.nil?
        return false if version != 0 # Only version 0 supported
        return false if num_entries.nil? || num_entries.negative?
        return false unless document_records

        true
      end

      private

      # Parse SVG header (10 bytes)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @version = io.read(2).unpack1("n")
        @svg_document_list_offset = io.read(4).unpack1("N")
        @reserved = io.read(4).unpack1("N")
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless version.zero?
          raise CorruptedTableError,
                "Unsupported SVG version: #{version} (only version 0 supported)"
        end

        if svg_document_list_offset > raw_data.length
          raise CorruptedTableError,
                "Invalid svgDocumentListOffset: #{svg_document_list_offset}"
        end
      end

      # Parse document index
      #
      # @param io [StringIO] Input stream
      def parse_document_index(io)
        # Seek to document index
        io.seek(svg_document_list_offset)

        # Check if there's enough data to read num_entries
        return if io.eof?

        # Parse number of entries
        num_entries_data = io.read(2)
        return if num_entries_data.nil? || num_entries_data.length < 2

        @num_entries = num_entries_data.unpack1("n")
        @document_records = []

        return if num_entries.zero?

        # Parse each document record (12 bytes each)
        num_entries.times do
          record_data = io.read(12)
          record = SvgDocumentRecord.read(record_data)
          @document_records << record
        end
      end

      # Find document record for a specific glyph ID
      #
      # Uses binary search since document records should be sorted by glyph ID.
      #
      # @param glyph_id [Integer] Glyph ID to find
      # @return [SvgDocumentRecord, nil] Document record or nil if not found
      def find_document_record(glyph_id)
        # Binary search through document records
        left = 0
        right = document_records.length - 1

        while left <= right
          mid = (left + right) / 2
          record = document_records[mid]

          if record.includes_glyph?(glyph_id)
            return record
          elsif glyph_id < record.start_glyph_id
            right = mid - 1
          else
            left = mid + 1
          end
        end

        nil
      end

      # Extract SVG document from record
      #
      # Calculates absolute offset and extracts SVG data.
      # Automatically decompresses gzipped content.
      #
      # @param record [SvgDocumentRecord] Document record
      # @return [String] SVG XML content
      def extract_svg_document(record)
        # Calculate absolute offset
        # Offset is relative to start of SVG Document List
        # Document List = numEntries (2 bytes) + entries array + documents
        documents_offset = svg_document_list_offset + 2 + (num_entries * 12)
        absolute_offset = documents_offset + record.svg_doc_offset

        # Extract SVG data
        svg_data = raw_data[absolute_offset, record.svg_doc_length]

        # Check if compressed (gzip magic bytes: 0x1f 0x8b)
        if gzipped?(svg_data)
          decompress_gzip(svg_data)
        else
          svg_data
        end
      end

      # Check if data is gzipped
      #
      # @param data [String] Binary data
      # @return [Boolean] True if gzipped
      def gzipped?(data)
        return false if data.nil? || data.length < 2

        data[0..1].unpack("C*") == [0x1f, 0x8b]
      end

      # Decompress gzipped data
      #
      # @param data [String] Gzipped binary data
      # @return [String] Decompressed data
      def decompress_gzip(data)
        Zlib::GzipReader.new(StringIO.new(data)).read
      rescue Zlib::Error => e
        raise CorruptedTableError, "Failed to decompress SVG data: #{e.message}"
      end
    end
  end
end
