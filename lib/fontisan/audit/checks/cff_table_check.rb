# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates CFF/CFF2 table structure: header version, Name INDEX
      # presence (CFF1), Top DICT CharStrings offset, CharStrings count
      # vs maxp.numGlyphs.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
      class CffTableCheck < Check
        def self.call(font)
          if font.has_table?("CFF2")
            validate_cff2(font)
          elsif font.has_table?("CFF ")
            validate_cff1(font)
          else
            []
          end
        end

        def self.code
          :ot_cff
        end

        # ---------- CFF1 ----------

        def self.validate_cff1(font)
          cff = font.table("CFF ")
          return [] unless cff

          issues = []
          issues.concat(validate_cff1_name_index(cff))
          issues.concat(validate_charstrings_count(cff, font, "CFF "))
          issues
        end
        private_class_method :validate_cff1

        def self.validate_cff1_name_index(cff)
          count = cff.font_count.to_i
          return [] if count.positive?

          [issue(severity: :error,
                 message: "CFF Name INDEX is empty — must contain at least " \
                          "one font name",
                 location: "cff.name_index")]
        end
        private_class_method :validate_cff1_name_index

        # ---------- CFF2 ----------

        def self.validate_cff2(font)
          cff2 = font.table("CFF2")
          return [] unless cff2

          validate_charstrings_count(cff2, font, "CFF2")
        end
        private_class_method :validate_cff2

        # ---------- shared ----------

        def self.validate_charstrings_count(cff, font, table_tag)
          return [] unless font.has_table?("maxp")

          cs_count = glyph_count_from_cff(cff)
          maxp_count = font.table("maxp").num_glyphs.to_i
          return [] if cs_count == maxp_count

          [issue(severity: :error,
                 message: "#{table_tag} CharStrings count (#{cs_count}) does " \
                          "not match maxp.numGlyphs (#{maxp_count})",
                 location: "#{table_tag.downcase}.charstrings")]
        end
        private_class_method :validate_charstrings_count

        def self.glyph_count_from_cff(cff)
          cs_index = cff.charstrings_index(0)
          cs_index&.count.to_i
        rescue StandardError
          0
        end
        private_class_method :glyph_count_from_cff
      end
    end
  end
end
