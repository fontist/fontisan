# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Audit::Checks::OpenTypeConformanceCheck do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe ".call" do
    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each do |i|
        expect(i).to be_a(Fontisan::Models::ValidationReport::Issue)
        expect(i.category).to eq("opentype_conformance")
      end
    end

    it "validates hhea.numberOfHMetrics ≤ numGlyphs" do
      issues = described_class.call(font)
      hhea_issues = issues.select { |i| i.location&.include?("number_of_h_metrics") }
      expect(hhea_issues).to be_empty
    end

    it "does not produce name-table issues (owned by NameTableCheck)" do
      issues = described_class.call(font)
      name_issues = issues.select { |i| i.location&.include?("nameID") }
      expect(name_issues).to be_empty
    end

    it "does not produce fsSelection issues (owned by Os2Check)" do
      issues = described_class.call(font)
      fs_issues = issues.select { |i| i.location&.include?("fs_selection") }
      expect(fs_issues).to be_empty
    end
  end

  describe ".code" do
    it "returns :opentype_conformance" do
      expect(described_class.code).to eq(:opentype_conformance)
    end
  end

  describe "CheckRegistry integration" do
    it "is included in the :default profile" do
      checks = Fontisan::Audit::CheckRegistry.for(:default)
      expect(checks).to include(described_class)
    end

    it "is included in the :spec profile" do
      checks = Fontisan::Audit::CheckRegistry.for(:spec)
      expect(checks).to include(described_class)
    end

    it "is included in the :structural profile" do
      checks = Fontisan::Audit::CheckRegistry.for(:structural)
      expect(checks).to include(described_class)
    end
  end
end
