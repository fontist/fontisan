# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Font Validation Integration" do
  let(:ttf_font_path) do
    File.join(__dir__, "..", "fixtures", "fonts", "MonaSans", "MonaSans",
              "ttf", "MonaSans-ExtraLightItalic.ttf")
  end

  describe "end-to-end validation" do
    it "validates a real TrueType font" do
      font = Fontisan::FontLoader.load(ttf_font_path)
      validator = Fontisan::Validation::Validator.new(level: :standard)

      report = validator.validate(font, ttf_font_path)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.font_path).to eq(ttf_font_path)
      expect(report.valid).to be(true)
    end

    it "generates report with correct structure" do
      font = Fontisan::FontLoader.load(ttf_font_path)
      validator = Fontisan::Validation::Validator.new(level: :standard)

      report = validator.validate(font, ttf_font_path)

      expect(report.summary).to be_a(Fontisan::Models::ValidationReport::Summary)
      expect(report.issues).to be_an(Array)
      expect(report.summary.errors).to be >= 0
      expect(report.summary.warnings).to be >= 0
      expect(report.summary.info).to be >= 0
    end
  end

  describe "validation levels" do
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

    it "validates with strict level" do
      validator = Fontisan::Validation::Validator.new(level: :strict)
      report = validator.validate(font, ttf_font_path)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
    end

    it "validates with standard level" do
      validator = Fontisan::Validation::Validator.new(level: :standard)
      report = validator.validate(font, ttf_font_path)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.valid).to be true
    end

    it "validates with lenient level" do
      validator = Fontisan::Validation::Validator.new(level: :lenient)
      report = validator.validate(font, ttf_font_path)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
      expect(report.valid).to be true
    end
  end

  describe "report serialization" do
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }
    let(:validator) { Fontisan::Validation::Validator.new(level: :standard) }

    it "serializes report to YAML" do
      report = validator.validate(font, ttf_font_path)
      yaml = report.to_yaml

      expect(yaml).to include("font_path:")
      expect(yaml).to include("valid:")
    end

    it "serializes report to JSON" do
      report = validator.validate(font, ttf_font_path)
      json = report.to_json

      expect(json).to include('"font_path":')
      expect(json).to include('"valid":')
    end

    it "generates text summary" do
      report = validator.validate(font, ttf_font_path)
      summary = report.text_summary

      expect(summary).to include("Font:")
      expect(summary).to include("Status:")
      expect(summary).to include("Summary:")
      expect(summary).to include("Errors:")
      expect(summary).to include("Warnings:")
    end
  end

  describe "table validation" do
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }
    let(:validator) { Fontisan::Validation::Validator.new(level: :standard) }

    it "checks for required tables" do
      validator.validate(font, ttf_font_path)

      # Required tables should be present in a valid font
      expect(font.has_table?("head")).to be true
      expect(font.has_table?("name")).to be true
      expect(font.has_table?("maxp")).to be true
    end
  end

  describe "structure validation" do
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }
    let(:validator) { Fontisan::Validation::Validator.new(level: :standard) }

    it "validates glyph count consistency" do
      validator.validate(font, ttf_font_path)
      maxp = font.table("maxp")

      expect(maxp.num_glyphs).to be > 0
      expect(maxp.num_glyphs).to be < 65536
    end

    it "validates table offsets" do
      validator.validate(font, ttf_font_path)

      font.tables.each do |table_entry|
        expect(table_entry.offset).to be >= 12
      end
    end
  end

  describe "consistency validation" do
    let(:font) { Fontisan::FontLoader.load(ttf_font_path) }
    let(:validator) { Fontisan::Validation::Validator.new(level: :standard) }

    it "validates hmtx consistency" do
      validator.validate(font, ttf_font_path)

      if font.has_table?("hmtx") && font.has_table?("hhea") && font.has_table?("maxp")
        hhea = font.table("hhea")
        maxp = font.table("maxp")

        expect(hhea.number_of_h_metrics).to be >= 1
        expect(hhea.number_of_h_metrics).to be <= maxp.num_glyphs
      end
    end

    it "validates name table presence" do
      validator.validate(font, ttf_font_path)

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
      font = Fontisan::FontLoader.load(ttf_font_path)
      validator = Fontisan::Validation::Validator.new(level: :standard)

      # Should not raise, should capture errors in report
      expect { validator.validate(font, ttf_font_path) }.not_to raise_error
    end
  end
end
