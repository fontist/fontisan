# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `hmtx` (horizontal metrics) table.
      # One LongHorMetric per glyph (4 bytes each):
      #   uint16 advanceWidth, int16 lsb
      # No trailing "leftSideBearing" array (use numberOfHMetrics = numGlyphs).
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/hmtx
      module Hmtx
        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String] hmtx table bytes
        def self.build(font, glyphs:)
          upm = font.info.units_per_em&.to_i || 1000
          data = +""
          glyphs.each do |glyph|
            bbox = glyph.bbox
            lsb = bbox ? bbox.x_min.to_i : 0
            width = glyph.width.to_i

            # Safety net: never emit advance_width=0 for a non-empty
            # glyph. This happens when donor hmtx parsing fails during
            # stitching and the width wasn't caught upstream.
            if width <= 0
              width = bbox ? (bbox.x_max.to_i - bbox.x_min.to_i) : upm
              width = [width, upm].max
            end

            data << [width, lsb].pack("nn")
          end
          data
        end
      end
    end
  end
end
