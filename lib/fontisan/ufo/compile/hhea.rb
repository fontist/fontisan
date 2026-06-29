# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `hhea` (horizontal header) table.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/hhea
      module Hhea
        VERSION_1_0 = 0x00010000

        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>]
        # @return [Fontisan::Tables::Hhea]
        def self.build(font, glyphs:)
          info = font.info
          widths = glyphs.map { |g| g.width.to_i }
          Fontisan::Tables::Hhea.new(
            version_raw: VERSION_1_0,
            ascent: info.ascender || 800,
            descent: info.descender || -200,
            line_gap: info.open_type_hhea_line_gap || 0,
            advance_width_max: widths.max || 0,
            min_left_side_bearing: 0,
            min_right_side_bearing: 0,
            x_max_extent: widths.max || 0,
            caret_slope_rise: 1,
            caret_slope_run: 0,
            caret_offset: 0,
            metric_data_format: 0,
            number_of_h_metrics: glyphs.size,
          )
        end
      end
    end
  end
end
