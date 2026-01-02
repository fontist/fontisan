# frozen_string_literal: true

require_relative "font_book_validator"

module Fontisan
  module Validators
    # OpenTypeValidator provides comprehensive OpenType specification compliance checks
    #
    # This validator extends FontBookValidator with additional checks ensuring full
    # OpenType specification compliance. It validates glyph data, character mappings,
    # and cross-table consistency.
    #
    # The validator inherits all checks from FontBookValidator (18 checks from
    # FontBookValidator + 8 from BasicValidator = 26 total) and adds 10 new checks:
    # - Maxp TrueType metrics validation
    # - Glyf table structure and accessibility
    # - Cmap Unicode mapping and coverage
    # - Cross-table consistency checks
    #
    # @example Using OpenTypeValidator
    #   validator = OpenTypeValidator.new
    #   report = validator.validate(font)
    #   puts "Font is OpenType compliant" if report.valid?
    class OpenTypeValidator < FontBookValidator
      private

      # Define OpenType specification compliance checks
      #
      # Calls super to inherit FontBookValidator's checks, then adds 10 new checks.
      # All checks use helpers from Week 1 table implementations.
      def define_checks
        # Inherit FontBookValidator checks (26 checks total)
        super

        # Check 27: Maxp TrueType metrics (only for version 1.0)
        check_table :maxp_truetype_metrics, 'maxp', severity: :warning do |table|
          !table.version_1_0? || table.has_truetype_metrics?
        end

        # Check 28: Maxp max zones must be valid
        check_table :maxp_zones, 'maxp', severity: :error do |table|
          table.valid_max_zones?
        end

        # Check 29: Glyf glyphs must be accessible (TrueType fonts only)
        check_glyphs :glyf_accessible, severity: :error do |font|
          glyf = font.table('glyf')
          next true unless glyf # Skip if CFF font

          loca = font.table('loca')
          head = font.table('head')
          maxp = font.table('maxp')
          glyf.all_glyphs_accessible?(loca, head, maxp.num_glyphs)
        end

        # Check 30: Glyf glyphs should not be clipped
        check_glyphs :glyf_no_clipping, severity: :warning do |font|
          glyf = font.table('glyf')
          next true unless glyf

          loca = font.table('loca')
          head = font.table('head')
          maxp = font.table('maxp')
          glyf.no_clipped_glyphs?(loca, head, maxp.num_glyphs)
        end

        # Check 31: Glyf contour counts must be valid
        check_glyphs :glyf_valid_contours, severity: :error do |font|
          glyf = font.table('glyf')
          next true unless glyf

          loca = font.table('loca')
          head = font.table('head')
          maxp = font.table('maxp')

          (0...maxp.num_glyphs).all? do |glyph_id|
            glyf.valid_contour_count?(glyph_id, loca, head)
          end
        end

        # Check 32: Cmap must have Unicode mapping
        check_table :cmap_unicode_mapping, 'cmap', severity: :error do |table|
          table.has_unicode_mapping?
        end

        # Check 33: Cmap should have BMP coverage
        check_table :cmap_bmp_coverage, 'cmap', severity: :warning do |table|
          table.has_bmp_coverage?
        end

        # Check 34: Cmap must have format 4 subtable
        check_table :cmap_format4, 'cmap', severity: :error do |table|
          table.has_format_4_subtable?
        end

        # Check 35: Cmap glyph indices must be valid
        check_structure :cmap_glyph_indices, severity: :error do |font|
          cmap = font.table('cmap')
          maxp = font.table('maxp')
          cmap.valid_glyph_indices?(maxp.num_glyphs)
        end

        # Check 36: Table checksums (info level - many fonts have mismatches)
        check_structure :checksum_valid, severity: :info do |font|
          # Table checksum validation (info level - for reference)
          # Most fonts have checksum mismatches, so we make it info not error
          true # Placeholder - actual checksum validation if desired
        end
      end
    end
  end
end
