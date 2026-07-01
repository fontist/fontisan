# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Format-specific glyph-count caps.
    #
    # Both TTF and OTF (CFF1) cap at 65,535 because:
    #   - TTF: maxp.num_glyphs is uint16
    #   - OTF (CFF1): maxp.num_glyphs is uint16 AND the CFF CharStrings
    #     INDEX count is card16
    #
    # Exceeding the cap produces a silently truncated font (the BinData
    # uint16 writer truncates without raising). The Stitcher checks
    # the cap BEFORE writing so the user gets a clear error.
    #
    # To exceed 65,535 glyphs, the font must be split into a TTC
    # (TrueType Collection) or fontisan must implement CFF2 (card24
    # INDEX counts). Both are future work.
    module GlyphLimit
      TTF_GLYPH_CAP = 65_535
      OTF_GLYPH_CAP = 65_535

      # @param format [Symbol] :ttf or :otf
      # @return [Integer, Float::INFINITY] the max glyph count
      def self.for_format(format)
        case format.to_sym
        when :ttf then TTF_GLYPH_CAP
        when :otf then OTF_GLYPH_CAP
        else
          raise ArgumentError, "unknown format: #{format.inspect}"
        end
      end

      # Raise GlyphLimitExceededError if `glyph_count` exceeds the cap
      # for the given format.
      #
      # @param glyph_count [Integer]
      # @param format [Symbol]
      # @raise [GlyphLimitExceededError]
      def self.check!(glyph_count, format:)
        limit = for_format(format)
        return if glyph_count <= limit

        raise GlyphLimitExceededError.new(
          actual: glyph_count,
          limit: limit,
          format: format,
        )
      end
    end
  end
end
