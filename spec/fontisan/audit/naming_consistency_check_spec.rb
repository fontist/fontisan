# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Audit::Checks::NamingConsistencyCheck do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe ".call" do
    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each do |i|
        expect(i).to be_a(Fontisan::Models::ValidationReport::Issue)
        expect(i.category).to eq("naming_consistency")
      end
    end

    it "checks PostScript name prefix against family name" do
      issues = described_class.call(font)
      ps_issues = issues.select { |i| i.location == "name.consistency.ps_prefix" }
      expect(ps_issues).to be_empty
    end

    it "checks full name composition" do
      issues = described_class.call(font)
      full_issues = issues.select { |i| i.location == "name.consistency.full_name" }
      expect(full_issues).to be_an(Array)
    end
  end

  describe ".code" do
    it "returns :naming_consistency" do
      expect(described_class.code).to eq(:naming_consistency)
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

    it "is included in the :layout profile" do
      checks = Fontisan::Audit::CheckRegistry.for(:layout)
      expect(checks).to include(described_class)
    end
  end
end
