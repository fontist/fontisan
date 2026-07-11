# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'hhea' table per the OpenType spec.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/hhea
      class HheaCheck < Check
        def self.call(font)
          return [] unless font.has_table?("hhea")

          hhea = font.table("hhea")
          issues = []
          issues.concat(validate_ascent(hhea))
          issues.concat(validate_descent(hhea))
          issues.concat(validate_line_gap(hhea))
          issues.concat(validate_advance_width_max(hhea))
          issues
        end

        def self.code
          :ot_hhea
        end

        def self.validate_ascent(hhea)
          return [] if hhea.ascent.to_i.positive?

          [issue(severity: :warning,
                 message: "hhea.ascent is #{hhea.ascent} but should be positive " \
                          "(ascender typically rises above the baseline)",
                 location: "hhea.ascent")]
        end
        private_class_method :validate_ascent

        def self.validate_descent(hhea)
          return [] if hhea.descent.to_i <= 0

          [issue(severity: :warning,
                 message: "hhea.descent is #{hhea.descent} but should be ≤ 0 " \
                          "(descender typically falls below the baseline)",
                 location: "hhea.descent")]
        end
        private_class_method :validate_descent

        def self.validate_line_gap(hhea)
          return [] if hhea.line_gap.to_i >= 0

          [issue(severity: :info,
                 message: "hhea.lineGap is #{hhea.line_gap} — negative line " \
                          "gap is unusual but not spec-prohibited",
                 location: "hhea.line_gap")]
        end
        private_class_method :validate_line_gap

        def self.validate_advance_width_max(hhea)
          return [] unless hhea.advance_width_max.to_i <= 0

          [issue(severity: :warning,
                 message: "hhea.advanceWidthMax is #{hhea.advance_width_max} " \
                          "but should be positive (the widest glyph advance)",
                 location: "hhea.advance_width_max")]
        end
        private_class_method :validate_advance_width_max
      end
    end
  end
end
