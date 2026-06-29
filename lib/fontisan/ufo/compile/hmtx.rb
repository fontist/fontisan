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
        # @param _font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] in gid order
        # @return [String] hmtx table bytes
        def self.build(_font, glyphs:)
          data = +""
          glyphs.each do |glyph|
            bbox = glyph.bbox
            lsb = bbox ? bbox.x_min.to_i : 0
            data << [glyph.width.to_i, lsb].pack("nn")
          end
          data
        end
      end
    end
  end
end
