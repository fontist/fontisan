# frozen_string_literal: true

module Fontisan
  module Tables
    # Parsed IndexSubTable from a CBLC table.
    #
    # The IndexSubTable is the format-specific directory describing how to
    # locate each glyph's bitmap inside CBDT. Five formats are defined by
    # the OpenType spec:
    #
    #   1 — variable metrics, variable size (uint32 offset array)
    #   2 — constant metrics, constant size (single imageSize for the range)
    #   3 — variable metrics, variable size, 4-byte-aligned (uint16 offsets × 4)
    #   4 — variable metrics, variable size, bit-packed offsets (rare)
    #   5 — constant metrics, constant size, with explicit uint32 offsetArray
    #
    # Each parsed IndexSubTable exposes one [CblcGlyphBitmapLocation] per
    # glyph in its range, plus the raw bytes so a subsetter can preserve
    # unchanged subtables verbatim if needed.
    #
    # Format-specific parsing is delegated to
    # [CblcIndexSubTableFormatParser]; this class only owns the data model.
    #
    # Reference: OpenType CBLC spec, IndexSubTable formats 1–5.
    class CblcIndexSubTable
      # @return [Integer] indexFormat field (1, 2, 3, or 5)
      attr_reader :index_format

      # @return [Integer] imageFormat field (e.g. 17 = small metrics + PNG)
      attr_reader :image_format

      # @return [Integer] absolute imageDataOffset from start of CBDT
      attr_reader :image_data_offset

      # @return [Integer] first glyph ID covered by this subtable
      attr_reader :first_glyph_index

      # @return [Integer] last glyph ID covered by this subtable
      attr_reader :last_glyph_index

      # @return [Array<CblcGlyphBitmapLocation>] one per glyph in range
      attr_reader :locations

      # @return [String] raw bytes of this IndexSubTable in the source CBLC
      attr_reader :raw_bytes

      def initialize(index_format:, image_format:, image_data_offset:,
                     first_glyph_index:, last_glyph_index:, locations:,
                     raw_bytes:)
        @index_format = index_format
        @image_format = image_format
        @image_data_offset = image_data_offset
        @first_glyph_index = first_glyph_index
        @last_glyph_index = last_glyph_index
        @locations = locations
        @raw_bytes = raw_bytes
      end

      # Parse an IndexSubTable from a CBLC binary blob.
      #
      # @param cblc_bytes [String] the full CBLC table bytes
      # @param index_subtable_offset [Integer] absolute byte offset within
      #   `cblc_bytes` where this IndexSubTable begins
      # @param first_glyph_index [Integer] first glyph ID covered
      # @param last_glyph_index [Integer] last glyph ID covered
      # @return [CblcIndexSubTable]
      def self.parse(cblc_bytes, index_subtable_offset:, first_glyph_index:,
                     last_glyph_index:)
        header = CblcIndexSubTableHeader.read(
          cblc_bytes[index_subtable_offset, 8],
        )

        new(
          index_format: header.index_format,
          image_format: header.image_format,
          image_data_offset: header.image_data_offset,
          first_glyph_index: first_glyph_index,
          last_glyph_index: last_glyph_index,
          locations: CblcIndexSubTableFormatParser.locations(
            header: header,
            bytes: cblc_bytes,
            base: index_subtable_offset,
            first: first_glyph_index,
            last: last_glyph_index,
          ),
          raw_bytes: CblcIndexSubTableFormatParser.raw_bytes(
            header: header,
            bytes: cblc_bytes,
            base: index_subtable_offset,
            first: first_glyph_index,
            last: last_glyph_index,
          ),
        )
      end

      # Number of glyphs covered by this subtable.
      #
      # @return [Integer]
      def glyph_count
        last_glyph_index - first_glyph_index + 1
      end
    end
  end
end
