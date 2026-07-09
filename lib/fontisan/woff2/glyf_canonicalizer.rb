# frozen_string_literal: true

module Fontisan
  module Woff2
    # Canonicalizes a source glyf table by padding each glyph to a 4-byte
    # boundary, matching fontTools' WOFF2 encoder behavior.
    #
    # fontTools' WOFF2 writer calls `_normaliseGlyfAndLoca(padding=4)` before
    # transforming the glyf table (see Lib/fontTools/ttLib/woff2.py). Each
    # glyph is recompiled with `recalcBBoxes=False`, which makes
    # `Glyph#compile` return the source glyph bytes verbatim, then the
    # glyf-table-level compile pads each glyph to the configured alignment.
    # The result is a glyf whose bytes match the source byte-for-byte
    # except for added padding (≤ 3 bytes per glyph).
    #
    # Chrome's OpenType Sanitizer (OTS) fails to reconstruct "unpadded"
    # glyf tables — see the long comment in WOFF2Writer.close():
    # https://github.com/google/woff2/issues/15
    # https://github.com/khaledhosny/ots/issues/60
    #
    # The canonical glyf is the bytes the WOFF2 transform encodes, the
    # bytes the decoder reconstructs, the bytes `glyf.origLength` reports,
    # and the bytes the SFNT checksum is computed over. All four must
    # agree.
    class GlyfCanonicalizer
      # @param glyf_data [String] Source glyf table bytes
      # @param loca_data [String] Source loca table bytes
      # @param num_glyphs [Integer] Glyph count from maxp
      # @param source_format [Integer] 0 (short loca) or 1 (long loca) —
      #   how to interpret the source loca
      # @param target_format [Integer] 0 (short loca) or 1 (long loca) —
      #   how to emit the canonical loca. Defaults to `source_format`.
      def initialize(glyf_data:, loca_data:, num_glyphs:, source_format:,
                     target_format: nil)
        @glyf_data = glyf_data
        @loca_data = loca_data
        @num_glyphs = num_glyphs
        @source_format = source_format
        @target_format = target_format || source_format
      end

      # @return [Hash{Symbol => String}] `{ glyf:, loca: }` where glyf is
      #   padded to 4-byte alignment per glyph and loca is emitted in
      #   `target_format`.
      def canonical
        glyf = String.new(encoding: Encoding::BINARY)
        new_offsets = [0]

        @num_glyphs.times do |i|
          start_offset = source_offsets[i]
          end_offset = source_offsets[i + 1]
          if start_offset < end_offset
            glyf << @glyf_data.byteslice(start_offset,
                                         end_offset - start_offset)
          end
          remainder = glyf.bytesize % 4
          glyf << ("\x00" * (4 - remainder)) if remainder.positive?
          new_offsets << glyf.bytesize
        end

        { glyf:, loca: build_loca(new_offsets) }
      end

      private

      def source_offsets
        @source_offsets ||= begin
          offsets = if @source_format.zero?
                      @loca_data.unpack("n*").map { |v| v * 2 }
                    else
                      @loca_data.unpack("N*")
                    end
          if offsets.length != @num_glyphs + 1
            raise InvalidFontError,
                  "loca has #{offsets.length} entries, expected #{@num_glyphs + 1}"
          end
          offsets
        end
      end

      def build_loca(offsets)
        if @target_format.zero?
          offsets.map { |o| o / 2 }.pack("n*")
        else
          offsets.pack("N*")
        end
      end
    end
  end
end
