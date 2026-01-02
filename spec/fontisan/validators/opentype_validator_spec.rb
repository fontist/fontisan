# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validators::OpenTypeValidator do
  let(:validator) { described_class.new }
  let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe "#validate" do
    let(:report) { validator.validate(font) }

    it "returns a ValidationReport" do
      expect(report).to be_a(Fontisan::Models::ValidationReport)
    end

    it "inherits FontBookValidator checks" do
      # Should include all 26 FontBookValidator checks
      font_book_checks = %w[
        required_tables name_version family_name postscript_name
        head_magic units_per_em num_glyphs reasonable_metrics
        name_windows_encoding name_mac_encoding os2_version
        os2_weight_class os2_width_class os2_vendor_id os2_panose
        os2_typo_metrics os2_win_metrics os2_unicode_ranges
        head_bounding_box hhea_ascent_descent hhea_line_gap
        hhea_metrics_count post_version post_italic_angle
        post_underline cmap_subtables
      ]

      performed_checks = report.checks_performed
      font_book_checks.each do |check_id|
        expect(performed_checks).to include(check_id)
      end
    end

    it "includes OpenTypeValidator-specific checks" do
      # Should include all 10 new checks
      opentype_checks = %w[
        maxp_truetype_metrics
        maxp_zones
        glyf_accessible
        glyf_no_clipping
        glyf_valid_contours
        cmap_unicode_mapping
        cmap_bmp_coverage
        cmap_format4
        cmap_glyph_indices
        checksum_valid
      ]

      performed_checks = report.checks_performed
      opentype_checks.each do |check_id|
        expect(performed_checks).to include(check_id)
      end
    end

    it "performs exactly 36 checks total" do
      expect(report.checks_performed.length).to eq(36)
    end

    context "with maxp validation" do
      it "validates TrueType metrics" do
        result = report.result_of(:maxp_truetype_metrics)
        expect(result).not_to be_nil
        expect(result.severity).to eq("warning")
      end

      it "validates max zones" do
        result = report.result_of(:maxp_zones)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end

    context "with glyf validation" do
      it "checks glyph accessibility" do
        result = report.result_of(:glyf_accessible)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end

      it "checks for clipped glyphs" do
        result = report.result_of(:glyf_no_clipping)
        expect(result).not_to be_nil
        expect(result.severity).to eq("warning")
      end

      it "validates contour counts" do
        result = report.result_of(:glyf_valid_contours)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end

    context "with cmap validation" do
      it "checks Unicode mapping" do
        result = report.result_of(:cmap_unicode_mapping)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end

      it "checks BMP coverage" do
        result = report.result_of(:cmap_bmp_coverage)
        expect(result).not_to be_nil
        expect(result.severity).to eq("warning")
      end

      it "checks format 4 subtable" do
        result = report.result_of(:cmap_format4)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end

      it "validates glyph indices" do
        result = report.result_of(:cmap_glyph_indices)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end

    context "with checksum validation" do
      it "includes checksum check as info level" do
        result = report.result_of(:checksum_valid)
        expect(result).not_to be_nil
        expect(result.severity).to eq("info")
      end
    end
  end

  describe "inheritance" do
    it "is a subclass of FontBookValidator" do
      expect(described_class.superclass).to eq(Fontisan::Validators::FontBookValidator)
    end
  end
end
