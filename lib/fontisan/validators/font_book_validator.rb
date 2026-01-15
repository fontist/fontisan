# frozen_string_literal: true

require_relative "basic_validator"

module Fontisan
  module Validators
    # FontBookValidator provides macOS Font Book installation compatibility checks
    #
    # This validator extends BasicValidator with additional checks needed for
    # fonts to be successfully installed and used in macOS Font Book. It ensures
    # proper encoding combinations, OS/2 metrics, and other macOS-specific
    # requirements.
    #
    # The validator inherits all 8 checks from BasicValidator and adds 12 new
    # checks focusing on:
    # - Name table encoding combinations (Windows and Mac)
    # - OS/2 table metrics and metadata
    # - Head table bounding box
    # - Hhea table metrics
    # - Post table metadata
    # - Cmap subtables
    #
    # @example Using FontBookValidator
    #   validator = FontBookValidator.new
    #   report = validator.validate(font)
    #   puts "Font is Font Book compatible" if report.valid?
    class FontBookValidator < BasicValidator
      private

      # Define Font Book compatibility checks
      #
      # Calls super to inherit BasicValidator's 8 checks, then adds 12 new checks.
      # All checks use helpers from Week 1 table implementations.
      def define_checks
        # Inherit BasicValidator checks (8 checks)
        super

        # Check 9: Name table Windows Unicode English encoding
        check_table :name_windows_encoding, "name", severity: :error do |table|
          table.has_valid_platform_combos?([3, 1, 0x0409]) # Windows Unicode English
        end

        # Check 10: Name table Mac Roman English encoding
        check_table :name_mac_encoding, "name", severity: :warning do |table|
          table.has_valid_platform_combos?([1, 0, 0]) # Mac Roman English
        end

        # Check 11: OS/2 table version must be valid
        check_table :os2_version, "OS/2", severity: :error, &:valid_version?

        # Check 12: OS/2 weight class must be valid (1-1000)
        check_table :os2_weight_class, "OS/2", severity: :error,
                    &:valid_weight_class?

        # Check 13: OS/2 width class must be valid (1-9)
        check_table :os2_width_class, "OS/2", severity: :error,
                    &:valid_width_class?

        # Check 14: OS/2 vendor ID should be present
        check_table :os2_vendor_id, "OS/2", severity: :warning, &:has_vendor_id?

        # Check 15: OS/2 PANOSE classification should be present
        check_table :os2_panose, "OS/2", severity: :info, &:has_panose?

        # Check 16: OS/2 typographic metrics must be valid
        check_table :os2_typo_metrics, "OS/2", severity: :error,
                    &:valid_typo_metrics?

        # Check 17: OS/2 Windows metrics must be valid
        check_table :os2_win_metrics, "OS/2", severity: :error,
                    &:valid_win_metrics?

        # Check 18: OS/2 Unicode ranges should be present
        check_table :os2_unicode_ranges, "OS/2", severity: :warning,
                    &:has_unicode_ranges?

        # Check 19: Head table bounding box must be valid
        check_table :head_bounding_box, "head", severity: :error,
                    &:valid_bounding_box?

        # Check 20: Hhea ascent/descent must be valid
        check_table :hhea_ascent_descent, "hhea", severity: :error,
                    &:valid_ascent_descent?

        # Check 21: Hhea line gap should be valid
        check_table :hhea_line_gap, "hhea", severity: :warning,
                    &:valid_line_gap?

        # Check 22: Hhea horizontal metrics count must be valid
        check_table :hhea_metrics_count, "hhea", severity: :error,
                    &:valid_number_of_h_metrics?

        # Check 23: Post table version must be valid
        check_table :post_version, "post", severity: :error, &:valid_version?

        # Check 24: Post table italic angle should be valid
        check_table :post_italic_angle, "post", severity: :warning,
                    &:valid_italic_angle?

        # Check 25: Post table underline metrics should be present
        check_table :post_underline, "post", severity: :info,
                    &:has_underline_metrics?

        # Check 26: Cmap table must have subtables
        check_table :cmap_subtables, "cmap", severity: :error, &:has_subtables?
      end
    end
  end
end
