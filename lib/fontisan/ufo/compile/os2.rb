# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `OS/2` table from UFO fontinfo data.
      # Default version is 4 (modern). Most fields are 0 unless the
      # UFO has explicit values.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/os2
      module Os2
        VERSION_DEFAULT = 4
        WEIGHT_REGULAR = 400
        WIDTH_NORMAL = 5
        FS_SELECTION_REGULAR = 0x0040

        # @param font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>] used to compute
        #   usFirstCharIndex/usLastCharIndex + xAvgCharWidth
        # @return [Fontisan::Tables::Os2]
        def self.build(font, glyphs:)
          info = font.info
          cp_min, cp_max = unicode_range(glyphs)
          Fontisan::Tables::Os2.new(
            version: VERSION_DEFAULT,
            x_avg_char_width: avg_advance(glyphs),
            us_weight_class: info.open_type_os2_weight_class || WEIGHT_REGULAR,
            us_width_class: info.open_type_os2_width_class || WIDTH_NORMAL,
            fs_type: 0,
            y_subscript_x_size: 650,
            y_subscript_y_size: 600,
            y_subscript_x_offset: 0,
            y_subscript_y_offset: 75,
            y_superscript_x_size: 650,
            y_superscript_y_size: 600,
            y_superscript_x_offset: 0,
            y_superscript_y_offset: 350,
            y_strikeout_size: 50,
            y_strikeout_position: 300,
            s_family_class: 0,
            panose: Array.new(10, 0),
            ul_unicode_range1: 1, # Basic Latin
            ul_unicode_range2: 0,
            ul_unicode_range3: 0,
            ul_unicode_range4: 0,
            ach_vend_id: "NONE",
            fs_selection: FS_SELECTION_REGULAR,
            us_first_char_index: cp_min,
            us_last_char_index: cp_max,
            s_typo_ascender: info.ascender || 800,
            s_typo_descender: info.descender || -200,
            s_typo_line_gap: info.open_type_hhea_line_gap || 0,
            us_win_ascent: info.ascender || 1000,
            us_win_descent: -(info.descender || -200),
            ul_code_page_range1: 1, # Latin 1
            ul_code_page_range2: 0,
            sx_height: info.x_height || 500,
            s_cap_height: info.cap_height || 700,
            us_default_char: 0,
            us_break_char: 0x20,
            us_max_context: 0,
          )
        end

        def self.unicode_range(glyphs)
          cps = glyphs.flat_map(&:unicodes).sort
          return [0xFFFF, 0] if cps.empty?

          [cps.first, cps.last]
        end
        private_class_method :unicode_range

        def self.avg_advance(glyphs)
          return 0 if glyphs.empty?

          (glyphs.sum { |g| g.width.to_i } / glyphs.size.to_f).round
        end
        private_class_method :avg_advance
      end
    end
  end
end
