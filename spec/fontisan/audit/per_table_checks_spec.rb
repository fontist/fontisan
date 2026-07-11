# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Per-table OT conformance checks" do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe Fontisan::Audit::Checks::HeadCheck do
    it ".code returns :ot_head" do
      expect(described_class.code).to eq(:ot_head)
    end

    it "returns issues for the head table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each do |i|
        expect(i.category).to eq("ot_head")
      end
    end
  end

  describe Fontisan::Audit::Checks::HheaCheck do
    it ".code returns :ot_hhea" do
      expect(described_class.code).to eq(:ot_hhea)
    end

    it "returns issues for the hhea table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_hhea") }
    end
  end

  describe Fontisan::Audit::Checks::MaxpCheck do
    it ".code returns :ot_maxp" do
      expect(described_class.code).to eq(:ot_maxp)
    end

    it "returns issues for the maxp table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_maxp") }
    end
  end

  describe Fontisan::Audit::Checks::Os2Check do
    it ".code returns :ot_os2" do
      expect(described_class.code).to eq(:ot_os2)
    end

    it "returns issues for the OS/2 table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_os2") }
    end

    it "validates usWeightClass range" do
      issues = described_class.call(font)
      weight_issues = issues.select { |i| i.location == "os2.us_weight_class" }
      expect(weight_issues).to be_empty
    end

    it "validates usWidthClass range" do
      issues = described_class.call(font)
      width_issues = issues.select { |i| i.location == "os2.us_width_class" }
      expect(width_issues).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::NameTableCheck do
    it ".code returns :ot_name" do
      expect(described_class.code).to eq(:ot_name)
    end

    it "returns issues for the name table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_name") }
    end

    it "validates required name IDs" do
      issues = described_class.call(font)
      name_id_issues = issues.select { |i| i.location&.include?("nameID") }
      expect(name_id_issues).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::PostCheck do
    it ".code returns :ot_post" do
      expect(described_class.code).to eq(:ot_post)
    end

    it "returns issues for the post table" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_post") }
    end
  end

  describe Fontisan::Audit::Checks::KernCheck do
    it ".code returns :ot_kern" do
      expect(described_class.code).to eq(:ot_kern)
    end

    it "returns empty when kern table is absent" do
      issues = described_class.call(font)
      expect(issues).to be_empty
    end
  end

  describe Fontisan::Audit::CheckRegistry do
    it ".for(:default) includes all 21 checks" do
      checks = described_class.for(:default)
      expect(checks.size).to eq(21)
    end

    it ".for(:spec) includes conformance + per-table checks" do
      checks = described_class.for(:spec)
      expect(checks.size).to eq(12)
      expect(checks).to include(Fontisan::Audit::Checks::OpenTypeConformanceCheck)
      expect(checks).to include(Fontisan::Audit::Checks::HeadCheck)
      expect(checks).to include(Fontisan::Audit::Checks::HheaCheck)
      expect(checks).to include(Fontisan::Audit::Checks::MaxpCheck)
      expect(checks).to include(Fontisan::Audit::Checks::Os2Check)
      expect(checks).to include(Fontisan::Audit::Checks::NameTableCheck)
      expect(checks).to include(Fontisan::Audit::Checks::PostCheck)
      expect(checks).to include(Fontisan::Audit::Checks::KernCheck)
    end

    it ".for(:per_table) returns the per-table checks" do
      checks = described_class.for(:per_table)
      expect(checks.size).to eq(10)
    end
  end
end
