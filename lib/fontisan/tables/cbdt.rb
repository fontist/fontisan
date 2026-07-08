# frozen_string_literal: true

module Fontisan
  module Tables
    # CBDT (Color Bitmap Data) table.
    #
    # CBDT stores the raw bitmap data blocks for color glyphs. CBLC indexes
    # into CBDT via `imageDataOffset` and per-glyph offset arrays. CBDT
    # itself is essentially a blob: the 4-byte header (majorVersion +
    # minorVersion) followed by an opaque sequence of bitmap blocks.
    #
    # This model exposes the header fields via BinData and preserves the
    # original bytes for subsetting and direct slicing. A Cbdt constructed
    # via `Cbdt.new` (no `read`) has no captured bytes — `raw_data` is nil
    # and `data_size` returns 0.
    #
    # Reference: OpenType CBDT specification.
    # https://learn.microsoft.com/en-us/typography/opentype/spec/cbdt
    #
    # @example Reading CBDT and slicing a bitmap block
    #   cbdt = Fontisan::Tables::Cbdt.read(font.table_data["CBDT"])
    #   bytes = cbdt.bitmap_data_at(120, 4096)
    class Cbdt < Binary::BaseRecord
      TAG = "CBDT"

      # CBDT v2.0 — original release
      VERSION_2_0 = 0x00020000
      # CBDT v3.0 — adds PNG image format support
      VERSION_3_0 = 0x00030000

      uint16 :major_version
      uint16 :minor_version

      # Whether this instance was populated from real table bytes.
      #
      # @return [Boolean]
      def has_raw_data?
        defined?(@raw_data) && !@raw_data.nil? ? true : false
      end

      # Raw bytes captured at read time, or nil for a fresh instance.
      #
      # @return [String, nil]
      def raw_data
        return @raw_data if defined?(@raw_data)

        nil
      end

      # Combined version number (e.g. 0x00030000 for v3.0).
      #
      # @return [Integer]
      def version
        (major_version << 16) | minor_version
      end

      # Total byte size of the captured CBDT bytes, or 0 if none.
      #
      # @return [Integer]
      def data_size
        raw_data&.bytesize || 0
      end

      # Whether `offset` falls within the captured CBDT byte range.
      #
      # @param offset [Integer, nil]
      # @return [Boolean]
      def valid_offset?(offset)
        return false if offset.nil? || offset.negative?

        offset < data_size
      end

      # Slice `length` bytes starting at `offset` from the CBDT blob.
      # Returns nil for out-of-range offsets/lengths so callers can use a
      # nil check instead of rescuing IndexError.
      #
      # @param offset [Integer, nil] start byte
      # @param length [Integer, nil] number of bytes
      # @return [String, nil]
      def bitmap_data_at(offset, length)
        return nil if offset.nil? || length.nil?
        return nil if offset.negative? || length.negative?
        return nil if offset + length > data_size

        raw_data[offset, length]
      end

      # Serialize the captured bytes back to binary. Falls back to BinData's
      # default serialization (4-byte header) if no bytes were captured,
      # so consumers can construct a CBDT from scratch.
      #
      # @return [String]
      def to_binary_s
        return raw_data if has_raw_data?

        super
      end

      # Whether the header declares a CBDT version fontisan understands
      # (v2.0 or v3.0) and any raw bytes were captured.
      #
      # @return [Boolean]
      def valid?
        return false unless [2, 3].include?(major_version)
        return false unless minor_version.zero?
        return false unless has_raw_data?

        true
      end
    end
  end
end
