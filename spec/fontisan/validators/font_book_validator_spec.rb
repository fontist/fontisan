# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validators::FontBookValidator do
  let(:validator) { described_class.new }
  let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe "#validate" do
    let(:report) { validator.validate(font) }

    it "returns a ValidationReport" do
      expect(report).to be_a(Fontisan::Models::ValidationReport)
    end

    it "inherits BasicValidator checks" do
      # Should include all 8 BasicValidator checks
      basic_checks = %w[
        required_tables
        name_version
        family_name
        postscript_name
        head_magic
        units_per_em
        num_glyphs
        reasonable_metrics
      ]

      performed_checks = report.checks_performed
      basic_checks.each do |check_id|
        expect(performed_checks).to include(check_id)
      end
    end

    it "includes FontBookValidator-specific checks" do
      # Should include all 18 new checks
      font_book_checks = %w[
        name_windows_encoding
        name_mac_encoding
        os2_version
        os2_weight_class
        os2_width_class
        os2_vendor_id
        os2_panose
        os2_typo_metrics
        os2_win_metrics
        os2_unicode_ranges
        head_bounding_box
        hhea_ascent_descent
        hhea_line_gap
        hhea_metrics_count
        post_version
        post_italic_angle
        post_underline
        cmap_subtables
      ]

      performed_checks = report.checks_performed
      font_book_checks.each do |check_id|
        expect(performed_checks).to include(check_id)
      end
    end

    it "performs exactly 26 checks total" do
      expect(report.checks_performed.length).to eq(26)
    end

    it "uses correct severity levels" do
      # Error-level checks
      error_checks = report.check_results.select { |cr| cr.severity == "error" }
      expect(error_checks.length).to be > 0

      # Warning-level checks
      warning_checks = report.check_results.select do |cr|
        cr.severity == "warning"
      end
      expect(warning_checks.length).to be > 0

      # Info-level checks
      info_checks = report.check_results.select { |cr| cr.severity == "info" }
      expect(info_checks.length).to be > 0
    end

    context "with valid font" do
      it "passes basic checks" do
        basic_result = report.result_of(:required_tables)
        expect(basic_result.passed).to be true
      end
    end

    context "with OS/2 table checks" do
      it "validates OS/2 version" do
        result = report.result_of(:os2_version)
        expect(result).not_to be_nil
        expect(result.table).to eq("OS/2")
      end

      it "validates OS/2 weight class" do
        result = report.result_of(:os2_weight_class)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end

      it "validates OS/2 width class" do
        result = report.result_of(:os2_width_class)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end

    context "with name table encoding checks" do
      it "checks Windows encoding" do
        result = report.result_of(:name_windows_encoding)
        expect(result).not_to be_nil
        expect(result.table).to eq("name")
        expect(result.severity).to eq("error")
      end

      it "checks Mac encoding" do
        result = report.result_of(:name_mac_encoding)
        expect(result).not_to be_nil
        expect(result.table).to eq("name")
        expect(result.severity).to eq("warning")
      end
    end

    context "with hhea table checks" do
      it "validates ascent/descent" do
        result = report.result_of(:hhea_ascent_descent)
        expect(result).not_to be_nil
        expect(result.table).to eq("hhea")
      end

      it "validates metrics count" do
        result = report.result_of(:hhea_metrics_count)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end
  end

  describe "inheritance" do
    it "is a subclass of BasicValidator" do
      expect(described_class.superclass).to eq(Fontisan::Validators::BasicValidator)
    end

    it "inherits BasicValidator functionality" do
      expect(validator).to respond_to(:validate)
    end
  end
end
