# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validators::WebFontValidator do
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

    it "includes WebFontValidator-specific checks" do
      # Should include all 10 new checks
      web_checks = %w[
        embedding_permissions
        os2_version_web
        no_complex_glyphs
        character_coverage
        cmap_bmp_web
        glyph_accessible_web
        head_bbox_web
        hhea_metrics_web
        woff_conversion_ready
        woff2_conversion_ready
      ]

      performed_checks = report.checks_performed
      web_checks.each do |check_id|
        expect(performed_checks).to include(check_id)
      end
    end

    it "performs exactly 18 checks total" do
      expect(report.checks_performed.length).to eq(18)
    end

    context "with embedding permissions" do
      it "validates OS/2 embedding permissions" do
        result = report.result_of(:embedding_permissions)
        expect(result).not_to be_nil
        expect(result.table).to eq("OS/2")
        expect(result.severity).to eq("error")
      end
    end

    context "with glyph complexity checks" do
      it "checks for complex glyphs" do
        result = report.result_of(:no_complex_glyphs)
        expect(result).not_to be_nil
        expect(result.severity).to eq("warning")
      end
    end

    context "with character coverage" do
      it "validates character coverage" do
        result = report.result_of(:character_coverage)
        expect(result).not_to be_nil
        expect(result.table).to eq("cmap")
        expect(result.severity).to eq("error")
      end

      it "checks BMP coverage" do
        result = report.result_of(:cmap_bmp_web)
        expect(result).not_to be_nil
        expect(result.severity).to eq("warning")
      end
    end

    context "with WOFF conversion readiness" do
      it "checks WOFF conversion readiness" do
        result = report.result_of(:woff_conversion_ready)
        expect(result).not_to be_nil
        expect(result.severity).to eq("info")
      end

      it "checks WOFF2 conversion readiness" do
        result = report.result_of(:woff2_conversion_ready)
        expect(result).not_to be_nil
        expect(result.severity).to eq("info")
      end
    end

    context "with glyph accessibility" do
      it "validates glyph accessibility for web" do
        result = report.result_of(:glyph_accessible_web)
        expect(result).not_to be_nil
        expect(result.severity).to eq("error")
      end
    end
  end

  describe "inheritance" do
    it "is a subclass of BasicValidator" do
      expect(described_class.superclass).to eq(Fontisan::Validators::BasicValidator)
    end

    it "does NOT inherit from FontBookValidator" do
      # WebFontValidator uses selective inheritance
      expect(described_class.superclass).not_to eq(Fontisan::Validators::FontBookValidator)
    end
  end
end
