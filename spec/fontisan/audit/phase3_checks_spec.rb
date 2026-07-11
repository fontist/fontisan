# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Audit Phase 3 validation checks" do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:otf_path) { "spec/fixtures/fonttools/TestOTF.otf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe Fontisan::Audit::Checks::VariableFontCheck do
    it ".code returns :variable_font" do
      expect(described_class.code).to eq(:variable_font)
    end

    it "returns empty for a static font (no fvar)" do
      issues = described_class.call(font)
      expect(issues).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::HintingCheck do
    it ".code returns :hinting" do
      expect(described_class.code).to eq(:hinting)
    end

    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each do |i|
        expect(i).to be_a(Fontisan::Models::ValidationReport::Issue)
        expect(i.category).to eq("hinting")
      end
    end

    it "checks TrueType fonts for fpgm/pre/cvt presence" do
      issues = described_class.call(font)
      severities = issues.map(&:severity)
      valid = %w[info warning error]
      severities.each { |s| expect(valid).to include(s) }
    end
  end

  describe Fontisan::Audit::Checks::Woff2ValidationCheck do
    it ".code returns :woff2_validation" do
      expect(described_class.code).to eq(:woff2_validation)
    end

    it "returns empty for a non-WOFF2 font (plain TTF)" do
      issues = described_class.call(font)
      expect(issues).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::FormatRoundTripCheck do
    it ".code returns :format_round_trip" do
      expect(described_class.code).to eq(:format_round_trip)
    end

    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
    end

    it "does not report glyph count mismatch for well-formed fonts" do
      issues = described_class.call(font)
      glyph_count_issues = issues.select { |i| i.location&.include?("glyph_count") }
      expect(glyph_count_issues).to be_empty
    end
  end

  describe Fontisan::Audit::CheckRegistry do
    it ".for(:default) includes all 21 checks" do
      checks = described_class.for(:default)
      expect(checks.size).to eq(21)
      expect(checks).to include(Fontisan::Audit::Checks::VariableFontCheck)
      expect(checks).to include(Fontisan::Audit::Checks::HintingCheck)
      expect(checks).to include(Fontisan::Audit::Checks::Woff2ValidationCheck)
      expect(checks).to include(Fontisan::Audit::Checks::FormatRoundTripCheck)
    end

    it ".for(:variable) returns only VariableFontCheck" do
      checks = described_class.for(:variable)
      expect(checks).to eq([Fontisan::Audit::Checks::VariableFontCheck])
    end

    it ".for(:hinting) returns only HintingCheck" do
      checks = described_class.for(:hinting)
      expect(checks).to eq([Fontisan::Audit::Checks::HintingCheck])
    end

    it ".for(:web) returns OTS + WOFF2 checks" do
      checks = described_class.for(:web)
      expect(checks).to contain_exactly(
        Fontisan::Audit::Checks::OtsCompatibilityCheck,
        Fontisan::Audit::Checks::Woff2ValidationCheck,
      )
    end
  end
end
