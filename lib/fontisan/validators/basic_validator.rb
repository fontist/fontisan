# frozen_string_literal: true

require_relative "validator"

module Fontisan
  module Validators
    # BasicValidator provides minimal validation for fast font indexing
    #
    # This validator implements only essential checks needed for font discovery
    # and indexing systems (e.g., Fontist). It is optimized for speed with a
    # target performance of < 50ms per font.
    #
    # The validator checks only critical font identification and structural
    # integrity, making it suitable for:
    # - Font discovery and indexing
    # - Quick font database updates
    # - Large-scale font scanning
    #
    # @example Using BasicValidator
    #   validator = BasicValidator.new
    #   report = validator.validate(font)
    #   puts "Font is valid for indexing" if report.valid?
    #
    # @example Target performance
    #   # Should complete in < 50ms
    #   start_time = Time.now
    #   report = BasicValidator.new.validate(font)
    #   elapsed = Time.now - start_time
    #   puts "Validated in #{elapsed * 1000}ms"
    class BasicValidator < Validator
      private

      # Define essential validation checks
      #
      # This validator implements 8 checks covering:
      # - Required tables presence
      # - Name table identification
      # - Head table integrity
      # - Maxp table glyph count
      #
      # All checks use helpers from Week 1 table implementations.
      def define_checks
        # Check 1: Required tables must be present
        check_structure :required_tables, severity: :error do |font|
          %w[name head maxp hhea].all? { |tag| font.table(tag) }
        end

        # Check 2: Name table version must be valid (0 or 1)
        check_table :name_version, "name", severity: :error, &:valid_version?

        # Check 3: Family name must be present and non-empty
        check_table :family_name, "name", severity: :error,
                    &:family_name_present?

        # Check 4: PostScript name must be valid (alphanumeric + hyphens)
        check_table :postscript_name, "name", severity: :error,
                    &:postscript_name_valid?

        # Check 5: Head table magic number must be correct
        check_table :head_magic, "head", severity: :error, &:valid_magic?

        # Check 6: Units per em must be valid (16-16384)
        check_table :units_per_em, "head", severity: :error,
                    &:valid_units_per_em?

        # Check 7: Number of glyphs must be at least 1 (.notdef)
        check_table :num_glyphs, "maxp", severity: :error, &:valid_num_glyphs?

        # Check 8: Maxp metrics should be reasonable (not absurd values)
        check_table :reasonable_metrics, "maxp", severity: :warning,
                    &:reasonable_metrics?
      end
    end
  end
end
