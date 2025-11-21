# frozen_string_literal: true

module Fontisan
  module Validation
    # ConsistencyValidator validates cross-table consistency
    #
    # This validator ensures that references between tables are valid,
    # such as cmap glyph references, hmtx entry counts, and variable
    # font table consistency.
    #
    # Single Responsibility: Cross-table data consistency validation
    #
    # @example Validating consistency
    #   validator = ConsistencyValidator.new(rules)
    #   issues = validator.validate(font)
    class ConsistencyValidator
      # Initialize consistency validator
      #
      # @param rules [Hash] Validation rules configuration
      def initialize(rules)
        @rules = rules
        @consistency_config = rules["consistency_checks"] || {}
      end

      # Validate font consistency
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font to validate
      # @return [Array<Hash>] Array of validation issues
      def validate(font)
        issues = []

        # Check hmtx consistency if enabled
        issues.concat(check_hmtx_consistency(font)) if should_check?("check_hmtx_consistency")

        # Check name table consistency if enabled
        issues.concat(check_name_consistency(font)) if should_check?("check_name_consistency")

        # Check variable font consistency if enabled
        issues.concat(check_variable_consistency(font)) if should_check?("check_variable_consistency")

        issues
      end

      private

      # Check if a validation should be performed
      #
      # @param check_name [String] The check name
      # @return [Boolean] true if check should be performed
      def should_check?(check_name)
        @rules.dig("validation_levels", "standard", check_name)
      end

      # Check hmtx entry count matches glyph count
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of hmtx consistency issues
      def check_hmtx_consistency(font)
        issues = []

        hmtx = font.table(Constants::HMTX_TAG)
        maxp = font.table(Constants::MAXP_TAG)
        hhea = font.table(Constants::HHEA_TAG)

        return issues unless hmtx && maxp && hhea

        glyph_count = maxp.num_glyphs
        num_of_long_hor_metrics = hhea.number_of_h_metrics

        # Verify the structure makes sense
        if num_of_long_hor_metrics > glyph_count
          issues << {
            severity: "error",
            category: "consistency",
            message: "hhea number_of_h_metrics (#{num_of_long_hor_metrics}) exceeds glyph count (#{glyph_count})",
            location: "hhea/hmtx tables",
          }
        end

        if num_of_long_hor_metrics < 1
          issues << {
            severity: "error",
            category: "consistency",
            message: "hhea number_of_h_metrics is #{num_of_long_hor_metrics}, must be at least 1",
            location: "hhea table",
          }
        end

        issues
      end

      # Check name table for consistency issues
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of name table issues
      def check_name_consistency(font)
        issues = []

        name = font.table(Constants::NAME_TAG)
        return issues unless name

        # Check that required name IDs are present
        required_name_ids = [
          Tables::Name::FAMILY,           # 1
          Tables::Name::SUBFAMILY,        # 2
          Tables::Name::FULL_NAME,        # 4
          Tables::Name::VERSION,          # 5
          Tables::Name::POSTSCRIPT_NAME,  # 6
        ]

        required_name_ids.each do |name_id|
          has_entry = name.name_records.any? do |record|
            record.name_id == name_id
          end
          unless has_entry
            issues << {
              severity: "warning",
              category: "consistency",
              message: "Missing recommended name ID #{name_id}",
              location: "name table",
            }
          end
        end

        # Check for duplicate entries (same platform/encoding/language/nameID)
        seen = {}
        name.name_records.each do |record|
          key = [record.platform_id, record.encoding_id, record.language_id,
                 record.name_id]
          if seen[key]
            issues << {
              severity: "warning",
              category: "consistency",
              message: "Duplicate name record: platform=#{record.platform_id}, encoding=#{record.encoding_id}, language=#{record.language_id}, nameID=#{record.name_id}",
              location: "name table",
            }
          end
          seen[key] = true
        end

        issues
      end

      # Check variable font table consistency
      #
      # @param font [TrueTypeFont, OpenTypeFont] The font
      # @return [Array<Hash>] Array of variable font issues
      def check_variable_consistency(font)
        issues = []

        # Only check if this is a variable font
        return issues unless font.has_table?(Constants::FVAR_TAG)

        fvar = font.table(Constants::FVAR_TAG)
        return issues unless fvar

        axis_count = fvar.axes.length

        # For TrueType variable fonts, check gvar consistency
        if font.has_table?(Constants::GVAR_TAG)
          gvar = font.table(Constants::GVAR_TAG)
          gvar_axis_count = gvar.axis_count
          if gvar_axis_count != axis_count
            issues << {
              severity: "error",
              category: "consistency",
              message: "fvar axis count (#{axis_count}) doesn't match gvar axis count (#{gvar_axis_count})",
              location: "fvar/gvar tables",
            }
          end
        end

        # Check that recommended variation tables are present
        unless font.has_table?(Constants::GVAR_TAG) || font.has_table?(Constants::CFF2_TAG)
          issues << {
            severity: "error",
            category: "consistency",
            message: "Variable font missing gvar (TrueType) or CFF2 (CFF) table",
            location: "variable font",
          }
        end

        # Check for recommended metrics variation tables
        unless font.has_table?(Constants::HVAR_TAG)
          issues << {
            severity: "info",
            category: "consistency",
            message: "Variable font missing HVAR table (recommended for better rendering)",
            location: nil,
          }
        end

        issues
      end
    end
  end
end
