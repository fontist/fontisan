# frozen_string_literal: true

module Fontisan
  module Woff2
    # Value object representing the loca table format.
    #
    # Per OpenType spec section 5.3.3 (indexToLocFormat):
    #   - SHORT (indexToLocFormat=0): offsets stored as offset/2 in uint16.
    #     Maximum addressable glyf offset is 0x1FFFE (131070) bytes. Each
    #     glyph's data must start at a 2-byte boundary.
    #   - LONG (indexToLocFormat=1): offsets stored as uint32. No alignment
    #     requirement; glyphs are concatenated back-to-back.
    #
    # Single source of truth for the format choice, alignment, entry width,
    # and loca size computation. `GlyfLocaTransform`, `GlyfLocaReconstruct`,
    # and the encoder all delegate to this object — they never inspect or
    # mutate the underlying integer code directly.
    #
    # fontTools' encoder prefers SHORT when the glyf table fits because
    # short loca is half the size of long loca. Chrome's OTS accepts both,
    # but rejects files where the format is inconsistent with the glyf
    # layout (e.g., short loca when glyf > 0x1FFFE, or unaligned glyphs
    # under short loca).
    class LocaFormat
      # Highest glyf offset addressable by short loca (uint16 max × 2).
      SHORT_GLYF_MAX = 0x1FFFE

      attr_reader :code, :alignment, :entry_width

      def initialize(code:, alignment:, entry_width:)
        @code = code
        @alignment = alignment
        @entry_width = entry_width
      end

      SHORT = new(code: 0, alignment: 2, entry_width: 2)
      LONG  = new(code: 1, alignment: 1, entry_width: 4)

      # Pick the most compact format that can address the given glyf size.
      # Short loca halves the loca table size, but cannot address glyf
      # offsets beyond 0x1FFFE.
      #
      # @param glyf_bytesize [Integer] reconstructed glyf table size
      # @return [LocaFormat] SHORT when it fits, LONG otherwise
      def self.choose_for(glyf_bytesize:)
        glyf_bytesize <= SHORT_GLYF_MAX ? SHORT : LONG
      end

      def short?
        code == SHORT.code
      end

      def long?
        code == LONG.code
      end

      # Bytes consumed by the loca table for a font with `num_glyphs` glyphs.
      #
      # @param num_glyphs [Integer]
      # @return [Integer]
      def loca_size(num_glyphs)
        entry_width * (num_glyphs + 1)
      end

      # Number of zero-pad bytes needed after `current_bytesize` to reach
      # the format's alignment boundary. Returns 0 when no padding is
      # required (already aligned, or LONG format which has alignment=1).
      #
      # @param current_bytesize [Integer]
      # @return [Integer]
      def padding_after(current_bytesize)
        return 0 if alignment == 1

        rem = current_bytesize % alignment
        rem.zero? ? 0 : alignment - rem
      end
    end
  end
end
