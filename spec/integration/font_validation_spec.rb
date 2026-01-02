# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Font Validation Integration" do
  let(:valid_font_path) do
    font_fixture_path("MonaSans",
                      "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")
  end

  describe "end-to-end validation" do
    it "validates a real TrueType font with production profile" do
      report = Fontisan.validate(valid_font_path, profile: :production)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      # font_path may be "unknown" if font object doesn't expose path
      expect(report.font_path).to be_a(String)
      # MonaSans fonts are high quality, should pass basic validation
    end

    it "generates report with correct structure" do
      report = Fontisan.validate(valid_font_path, profile: :production)

      expect(report.summary).to be_a(Fontisan::Models::ValidationReport::Summary)
      expect(report.issues).to be_an(Array)
      expect(report.summary.errors).to be >= 0
      expect(report.summary.warnings).to be >= 0
      expect(report.summary.info).to be >= 0
      expect(report.check_results).to be_an(Array)
    end
  end

  describe "validation profiles" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "validates with indexability profile" do
      report = Fontisan.validate(valid_font_path, profile: :indexability)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(8)
    end

    it "validates with usability profile" do
      report = Fontisan.validate(valid_font_path, profile: :usability)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(26)
    end

    it "validates with production profile" do
      report = Fontisan.validate(valid_font_path, profile: :production)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(36)
    end

    it "validates with web profile" do
      report = Fontisan.validate(valid_font_path, profile: :web)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(18)
    end

    it "validates with spec_compliance profile" do
      report = Fontisan.validate(valid_font_path, profile: :spec_compliance)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(36)
    end
  end

  describe "report serialization" do
    let(:report) { Fontisan.validate(valid_font_path, profile: :production) }

    it "serializes report to YAML" do
      yaml = report.to_yaml

      expect(yaml).to include("font_path:")
      expect(yaml).to include("valid:")
      expect(yaml).to include("checks_performed")
    end

    it "serializes report to JSON" do
      json = report.to_json

      expect(json).to include('"font_path":')
      expect(json).to include('"valid":')
      expect(json).to include('"checks_performed"')
    end

    it "generates text summary" do
      summary = report.text_summary

      expect(summary).to include("Font:")
      expect(summary).to include("Status:")
      expect(summary).to include("Summary:")
      expect(summary).to include("Errors:")
      expect(summary).to include("Warnings:")
    end

    it "generates brief summary" do
      summary = report.to_summary
      expect(summary).to match(/\d+ errors, \d+ warnings, \d+ info/)
    end

    it "generates table format" do
      table = report.to_table_format
      expect(table).to include("CHECK_ID | STATUS | SEVERITY | TABLE")
    end
  end

  describe "table validation" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "checks for required tables" do
      # Required tables should be present in a valid font
      expect(font.has_table?("head")).to be true
      expect(font.has_table?("name")).to be true
      expect(font.has_table?("maxp")).to be true
    end
  end

  describe "structure validation" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "validates glyph count consistency" do
      maxp = font.table("maxp")

      expect(maxp.num_glyphs).to be > 0
      expect(maxp.num_glyphs).to be < 65536
    end

    it "validates table offsets" do
      font.tables.each do |table_entry|
        expect(table_entry.offset).to be >= 12
      end
    end
  end

  describe "consistency validation" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "validates hmtx consistency" do
      if font.has_table?("hmtx") && font.has_table?("hhea") && font.has_table?("maxp")
        hhea = font.table("hhea")
        maxp = font.table("maxp")

        expect(hhea.number_of_h_metrics).to be >= 1
        expect(hhea.number_of_h_metrics).to be <= maxp.num_glyphs
      end
    end

    it "validates name table presence" do
      expect(font.has_table?("name")).to be true
    end
  end

  describe "error handling" do
    it "handles non-existent files gracefully" do
      expect do
        Fontisan::FontLoader.load("/nonexistent/font.ttf")
      end.to raise_error(Errno::ENOENT)
    end

    it "catches validation errors" do
      # Should not raise, should capture errors in report
      expect {
        Fontisan.validate(valid_font_path, profile: :production)
      }.not_to raise_error
    end
  end

  describe "direct validator usage" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "can use BasicValidator directly" do
      validator = Fontisan::Validators::BasicValidator.new
      report = validator.validate(font)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(8)
    end

    it "can use OpenTypeValidator directly" do
      validator = Fontisan::Validators::OpenTypeValidator.new
      report = validator.validate(font)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.checks_performed.length).to eq(36)
    end
  end
end
