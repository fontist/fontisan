# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Audits font hinting configuration. Hinting quality directly
      # affects small-size screen rendering (Windows, Android, embedded
      # systems).
      #
      # TrueType (glyf outlines):
      #   - fpgm (font program) presence recommended for hinted fonts
      #   - prep (control value program) presence recommended
      #   - cvt (control value table) presence recommended
      #   - maxp.maxStackElements and maxp.maxZones must be positive
      #     if any hinting instructions exist
      #   - gasp table recommended for controlling grid-fitting per ppem
      #
      # CFF (PostScript outlines):
      #   - Private DICT should have BlueValues or StdHW/StdVW for hinting
      #   - Subroutine usage (Local/Global subrs) recommended for size
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/ttinst#hinting-instructions
      class HintingCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          if font.has_table?("glyf")
            validate_truetype_hinting(font)
          elsif font.has_table?("CFF ") || font.has_table?("CFF2")
            validate_cff_hinting(font)
          else
            []
          end
        end

        def self.code
          :hinting
        end

        # ---------- TrueType hinting ----------

        def self.validate_truetype_hinting(font)
          issues = []
          has_fpgm = font.has_table?("fpgm")
          has_prep = font.has_table?("prep")
          has_cvt = font.has_table?("cvt")
          has_glyf_data = table_has_data?(font, "glyf")

          if has_fpgm && has_glyf_data
            issues.concat(validate_maxp_hint_capacity(font))
          end

          issues << no_program_warning("prep") if !has_prep && has_fpgm
          issues << no_program_warning("cvt") if !has_cvt && has_fpgm

          unless font.has_table?("gasp")
            issues << issue(severity: :info,
                            message: "TrueType font has no 'gasp' table — " \
                                     "grid-fitting behavior per ppem is " \
                                     "implementation-defined",
                            location: "tables.gasp")
          end

          issues
        end
        private_class_method :validate_truetype_hinting

        def self.validate_maxp_hint_capacity(font)
          issues = []
          maxp = font.table("maxp")
          return issues unless maxp.version_1_0?

          stack = maxp.max_stack_elements.to_i
          zones = maxp.max_zones.to_i
          if has_fpgm_instructions?(font) && stack.zero?
            issues << issue(severity: :warning,
                            message: "maxp.maxStackElements is 0 but the font " \
                                     "has hinting instructions — rendering " \
                                     "may fail",
                            location: "maxp.max_stack_elements")
          end
          unless zones.between?(1, 2)
            issues << issue(severity: :warning,
                            message: "maxp.maxZones is #{zones} but must be 1 or 2 " \
                                     "per the OpenType spec",
                            location: "maxp.max_zones")
          end
          issues
        end
        private_class_method :validate_maxp_hint_capacity

        def self.has_fpgm_instructions?(font)
          table_has_data?(font, "fpgm")
        end
        private_class_method :has_fpgm_instructions?

        def self.no_program_warning(table)
          issue(severity: :info,
                message: "Font has 'fpgm' but no '#{table}' table — " \
                         "#{table == 'cvt' ? 'control values' : 'pre-program'} " \
                         "are recommended for consistent hinting",
                location: "tables.#{table}")
        end
        private_class_method :no_program_warning

        # ---------- CFF hinting ----------

        def self.validate_cff_hinting(font)
          issues = []
          tag = font.has_table?("CFF2") ? "CFF2" : "CFF "
          cff = font.table(tag)
          return issues unless cff

          priv = begin
            cff.private_dict(0)
          rescue StandardError
            nil
          end
          return issues unless priv

          has_blues = priv_values?(priv, :blue_values) || priv_values?(priv, :other_blues)
          has_stems = priv_value?(priv, :std_hw) || priv_value?(priv, :std_vw)

          if !has_blues && !has_stems
            issues << issue(severity: :info,
                            message: "CFF Private DICT has no BlueValues or " \
                                     "StdHW/StdVW — alignment zones and stem " \
                                     "widths are the primary hinting mechanism " \
                                     "for CFF outlines",
                            location: "cff.private_dict")
          end

          issues
        end
        private_class_method :validate_cff_hinting

        def self.priv_values?(priv, key)
          val = priv[key] || priv[key.to_s]
          val.is_a?(Array) ? val.any? : false
        rescue StandardError
          false
        end
        private_class_method :priv_values?

        def self.priv_value?(priv, key)
          val = priv[key] || priv[key.to_s]
          val && !val.zero?
        rescue StandardError
          false
        end
        private_class_method :priv_value?

        # ---------- helpers ----------

        def self.table_has_data?(font, tag)
          raw = font.table_data[tag]
          raw && !raw.empty?
        end
        private_class_method :table_has_data?
      end
    end
  end
end
