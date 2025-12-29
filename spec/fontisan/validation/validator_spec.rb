# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validation::Validator do
  let(:valid_font_path) do
    font_fixture_path("MonaSans",
                      "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")
  end

  describe ".new" do
    it "creates a validator with default standard level" do
      validator = described_class.new

      expect(validator.level).to eq(:standard)
    end

    it "creates a validator with specified level" do
      validator = described_class.new(level: :strict)

      expect(validator.level).to eq(:strict)
    end

    it "raises error for invalid level" do
      expect do
        described_class.new(level: :invalid)
      end.to raise_error(ArgumentError, /Invalid validation level/)
    end

    it "accepts all supported levels" do
      %i[strict standard lenient].each do |level|
        expect { described_class.new(level: level) }.not_to raise_error
      end
    end
  end

  describe "#validate" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }
    let(:validator) { described_class.new(level: :standard) }

    it "returns a ValidationReport" do
      report = validator.validate(font, valid_font_path)

      expect(report).to be_a(Fontisan::Models::ValidationReport)
    end

    it "sets font_path in report" do
      report = validator.validate(font, valid_font_path)

      expect(report.font_path).to eq(valid_font_path)
    end

    it "validates a valid font" do
      report = validator.validate(font, valid_font_path)

      expect(report.valid).to be true
      expect(report.has_errors?).to be false
    end

    it "runs all validators" do
      # The real font should pass all enabled validations
      report = validator.validate(font, valid_font_path)

      expect(report.summary).to be_a(Fontisan::Models::ValidationReport::Summary)
      expect(report.issues).to be_an(Array)
    end

    context "with strict level" do
      let(:validator) { described_class.new(level: :strict) }

      it "validates with strict rules" do
        report = validator.validate(font, valid_font_path)

        # Strict level doesn't allow warnings
        expect(report).to be_a(Fontisan::Models::ValidationReport)
      end
    end

    context "with lenient level" do
      let(:validator) { described_class.new(level: :lenient) }

      it "validates with lenient rules" do
        report = validator.validate(font, valid_font_path)

        # Lenient level allows more issues
        expect(report).to be_a(Fontisan::Models::ValidationReport)
      end
    end

    context "when validation fails" do
      it "catches exceptions and adds them as errors" do
        # Create a validator that will fail
        allow_any_instance_of(Fontisan::Validation::TableValidator)
          .to receive(:validate).and_raise(StandardError, "Test error")

        report = validator.validate(font, valid_font_path)

        expect(report.valid).to be false
        expect(report.has_errors?).to be true
        expect(report.errors.first.message).to include("Test error")
      end
    end
  end

  describe "validation levels" do
    let(:font) { Fontisan::FontLoader.load(valid_font_path) }

    it "strict level rejects warnings" do
      validator = described_class.new(level: :strict)
      report = validator.validate(font, valid_font_path)

      # If there are warnings, strict should mark as invalid
      if report.has_warnings?
        expect(report.valid).to be false
      end
    end

    it "standard level allows warnings" do
      validator = described_class.new(level: :standard)
      report = validator.validate(font, valid_font_path)

      # Standard should be valid if no errors (even with warnings)
      unless report.has_errors?
        expect(report.valid).to be true
      end
    end

    it "lenient level is most permissive" do
      validator = described_class.new(level: :lenient)
      report = validator.validate(font, valid_font_path)

      # Lenient should be valid if no errors
      unless report.has_errors?
        expect(report.valid).to be true
      end
    end
  end

  describe "rules loading" do
    it "loads default validation rules" do
      validator = described_class.new

      # Should not raise error
      expect { validator }.not_to raise_error
    end

    it "raises error for non-existent rules file" do
      expect do
        described_class.new(rules_path: "/nonexistent/path.yml")
      end.to raise_error(/not found/)
    end
  end
end
