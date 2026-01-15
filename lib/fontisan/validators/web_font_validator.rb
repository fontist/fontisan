# frozen_string_literal: true

require_relative "basic_validator"

module Fontisan
  module Validators
    # WebFontValidator provides web font optimization and embedding compatibility checks
    #
    # This validator extends BasicValidator with checks specific to web font use cases.
    # Unlike FontBookValidator, it focuses on web embedding permissions, file size,
    # and WOFF/WOFF2 conversion readiness rather than desktop installation.
    #
    # The validator inherits 8 checks from BasicValidator and adds 10 new checks:
    # - Embedding permissions (OS/2 fsType)
    # - File size and glyph complexity for web performance
    # - Character coverage for web use
    # - Glyph accessibility
    # - WOFF/WOFF2 conversion readiness
    #
    # @example Using WebFontValidator
    #   validator = WebFontValidator.new
    #   report = validator.validate(font)
    #   puts "Font is web-ready" if report.valid?
    class WebFontValidator < BasicValidator
      private

      # Define web font validation checks
      #
      # Calls super to inherit BasicValidator's 8 checks, then adds 10 new checks.
      # All checks use helpers from Week 1 table implementations.
      def define_checks
        # Inherit BasicValidator checks (8 checks)
        super

        # Check 9: OS/2 embedding permissions must allow web use
        check_table :embedding_permissions, "OS/2", severity: :error,
                    &:has_embedding_permissions?

        # Check 10: OS/2 version should be present
        check_table :os2_version_web, "OS/2", severity: :warning,
                    &:valid_version?

        # Check 11: Glyph complexity should be reasonable for web
        check_glyphs :no_complex_glyphs, severity: :warning do |font|
          maxp = font.table("maxp")
          next true unless maxp.version_1_0?

          # Check max points and contours are reasonable for web rendering
          maxp.max_points && maxp.max_points < 3000 &&
            maxp.max_contours && maxp.max_contours < 500
        end

        # Check 12: Cmap must have Unicode mapping for web
        check_table :character_coverage, "cmap", severity: :error,
                    &:has_unicode_mapping?

        # Check 13: Cmap should have BMP coverage
        check_table :cmap_bmp_web, "cmap", severity: :warning,
                    &:has_bmp_coverage?

        # Check 14: Glyf glyphs must be accessible (web browsers need this)
        check_glyphs :glyph_accessible_web, severity: :error do |font|
          glyf = font.table("glyf")
          next true unless glyf

          loca = font.table("loca")
          head = font.table("head")
          maxp = font.table("maxp")
          glyf.all_glyphs_accessible?(loca, head, maxp.num_glyphs)
        end

        # Check 15: Head table must have valid bounding box
        check_table :head_bbox_web, "head", severity: :error,
                    &:valid_bounding_box?

        # Check 16: Hhea metrics must be valid for web rendering
        check_table :hhea_metrics_web, "hhea", severity: :error do |table|
          table.valid_ascent_descent? && table.valid_number_of_h_metrics?
        end

        # Check 17: WOFF conversion readiness
        check_structure :woff_conversion_ready, severity: :info do |font|
          # Check font can be converted to WOFF
          # All required tables present
          %w[name head maxp hhea].all? { |tag| font.table(tag) }
        end

        # Check 18: WOFF2 conversion readiness
        check_structure :woff2_conversion_ready, severity: :info do |font|
          # Check font can be converted to WOFF2
          # Same requirements as WOFF
          %w[name head maxp hhea].all? { |tag| font.table(tag) }
        end
      end
    end
  end
end
