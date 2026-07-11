# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Audit usability enhancements" do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe Fontisan::Models::AuditSummary do
    describe ".from_issues" do
      it "counts issues by severity" do
        issues = [
          Fontisan::Models::ValidationReport::Issue.new(severity: "error", category: "test", message: "e1"),
          Fontisan::Models::ValidationReport::Issue.new(severity: "error", category: "test", message: "e2"),
          Fontisan::Models::ValidationReport::Issue.new(severity: "warning", category: "test", message: "w1"),
          Fontisan::Models::ValidationReport::Issue.new(severity: "info", category: "test", message: "i1"),
        ]
        summary = described_class.from_issues(issues)
        expect(summary.error_count).to eq(2)
        expect(summary.warning_count).to eq(1)
        expect(summary.info_count).to eq(1)
        expect(summary.total).to eq(4)
      end

      it "passed is true when no errors" do
        issues = [
          Fontisan::Models::ValidationReport::Issue.new(severity: "warning", category: "test", message: "w"),
        ]
        summary = described_class.from_issues(issues)
        expect(summary.passed).to be true
      end

      it "passed is false when errors present" do
        issues = [
          Fontisan::Models::ValidationReport::Issue.new(severity: "error", category: "test", message: "e"),
        ]
        summary = described_class.from_issues(issues)
        expect(summary.passed).to be false
      end

      it "handles empty issue list" do
        summary = described_class.from_issues([])
        expect(summary.total).to eq(0)
        expect(summary.passed).to be true
      end
    end
  end

  describe Fontisan::Audit::Checks::CffTableCheck do
    it ".code returns :ot_cff" do
      expect(described_class.code).to eq(:ot_cff)
    end

    it "returns empty for a TrueType font (no CFF)" do
      expect(described_class.call(font)).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::GlyfTableCheck do
    it ".code returns :ot_glyf" do
      expect(described_class.code).to eq(:ot_glyf)
    end

    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_glyf") }
    end
  end

  describe Fontisan::Audit::Checks::LayoutTableCheck do
    it ".code returns :ot_layout" do
      expect(described_class.code).to eq(:ot_layout)
    end

    it "returns an Array of issues" do
      issues = described_class.call(font)
      expect(issues).to be_an(Array)
      issues.each { |i| expect(i.category).to eq("ot_layout") }
    end
  end

  describe Fontisan::Audit::CheckRegistry do
    it ".for(:default) includes all 20 checks" do
      checks = described_class.for(:default)
      expect(checks.size).to eq(20)
    end

    it ".for(:per_table) includes all 10 per-table checks" do
      checks = described_class.for(:per_table)
      expect(checks.size).to eq(10)
    end

    it ".for(:layout) includes glyph_names + cmap + ot_layout" do
      checks = described_class.for(:layout)
      expect(checks).to include(Fontisan::Audit::Checks::GlyphNameCheck)
      expect(checks).to include(Fontisan::Audit::Checks::CmapCheck)
      expect(checks).to include(Fontisan::Audit::Checks::LayoutTableCheck)
    end
  end

  describe "AuditCommand integration with summary" do
    it "populates validation_summary when validate: true" do
      cmd = Fontisan::Commands::AuditCommand.new(
        font_path, include_codepoints: false, validate: true
      )
      report = cmd.run
      expect(report.validation_summary).to be_a(Fontisan::Models::AuditSummary)
      expect(report.validation_summary.total).to eq(report.validation_issues.size)
    end
  end
end
