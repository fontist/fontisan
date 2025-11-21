# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::ValidationReport do
  describe ".new" do
    it "creates a new validation report" do
      report = described_class.new(
        font_path: "test.ttf",
        valid: true,
      )

      expect(report.font_path).to eq("test.ttf")
      expect(report.valid).to be true
      expect(report.issues).to be_empty
      expect(report.summary.errors).to eq(0)
      expect(report.summary.warnings).to eq(0)
      expect(report.summary.info).to eq(0)
    end
  end

  describe "#add_error" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "adds an error to the report" do
      report.add_error("tables", "Missing table: glyf", nil)

      expect(report.issues.length).to eq(1)
      expect(report.summary.errors).to eq(1)
      expect(report.valid).to be false
    end

    it "creates error with correct attributes" do
      report.add_error("tables", "Missing table: glyf", "glyf table")

      issue = report.issues.first
      expect(issue.severity).to eq("error")
      expect(issue.category).to eq("tables")
      expect(issue.message).to eq("Missing table: glyf")
      expect(issue.location).to eq("glyf table")
    end
  end

  describe "#add_warning" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "adds a warning to the report" do
      report.add_warning("checksum", "Checksum mismatch", "head table")

      expect(report.issues.length).to eq(1)
      expect(report.summary.warnings).to eq(1)
      expect(report.valid).to be true
    end

    it "creates warning with correct attributes" do
      report.add_warning("checksum", "Checksum mismatch", "head table")

      issue = report.issues.first
      expect(issue.severity).to eq("warning")
      expect(issue.category).to eq("checksum")
      expect(issue.message).to eq("Checksum mismatch")
      expect(issue.location).to eq("head table")
    end
  end

  describe "#add_info" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "adds an info message to the report" do
      report.add_info("optimization", "Could benefit from subsetting", nil)

      expect(report.issues.length).to eq(1)
      expect(report.summary.info).to eq(1)
      expect(report.valid).to be true
    end

    it "creates info with correct attributes" do
      report.add_info("optimization", "Could benefit from subsetting", nil)

      issue = report.issues.first
      expect(issue.severity).to eq("info")
      expect(issue.category).to eq("optimization")
      expect(issue.message).to eq("Could benefit from subsetting")
      expect(issue.location).to be_nil
    end
  end

  describe "#errors" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "returns only error issues" do
      report.add_error("tables", "Error 1", nil)
      report.add_warning("checksum", "Warning 1", nil)
      report.add_info("optimization", "Info 1", nil)
      report.add_error("structure", "Error 2", nil)

      errors = report.errors
      expect(errors.length).to eq(2)
      expect(errors.all? { |e| e.severity == "error" }).to be true
    end
  end

  describe "#warnings" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "returns only warning issues" do
      report.add_error("tables", "Error 1", nil)
      report.add_warning("checksum", "Warning 1", nil)
      report.add_warning("checksum", "Warning 2", nil)
      report.add_info("optimization", "Info 1", nil)

      warnings = report.warnings
      expect(warnings.length).to eq(2)
      expect(warnings.all? { |w| w.severity == "warning" }).to be true
    end
  end

  describe "#info_issues" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "returns only info issues" do
      report.add_error("tables", "Error 1", nil)
      report.add_warning("checksum", "Warning 1", nil)
      report.add_info("optimization", "Info 1", nil)
      report.add_info("optimization", "Info 2", nil)

      info = report.info_issues
      expect(info.length).to eq(2)
      expect(info.all? { |i| i.severity == "info" }).to be true
    end
  end

  describe "#has_errors?" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "returns true when errors exist" do
      report.add_error("tables", "Error", nil)
      expect(report.has_errors?).to be true
    end

    it "returns false when no errors exist" do
      report.add_warning("checksum", "Warning", nil)
      expect(report.has_errors?).to be false
    end
  end

  describe "#has_warnings?" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "returns true when warnings exist" do
      report.add_warning("checksum", "Warning", nil)
      expect(report.has_warnings?).to be true
    end

    it "returns false when no warnings exist" do
      report.add_error("tables", "Error", nil)
      expect(report.has_warnings?).to be false
    end
  end

  describe "#text_summary" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "generates text summary for valid font" do
      summary = report.text_summary

      expect(summary).to include("Font: test.ttf")
      expect(summary).to include("Status: VALID")
      expect(summary).to include("Errors: 0")
      expect(summary).to include("Warnings: 0")
      expect(summary).to include("Info: 0")
    end

    it "generates text summary for invalid font" do
      report.add_error("tables", "Missing table: glyf", nil)
      report.add_warning("checksum", "Checksum mismatch", "head table")

      summary = report.text_summary

      expect(summary).to include("Status: INVALID")
      expect(summary).to include("Errors: 1")
      expect(summary).to include("Warnings: 1")
      expect(summary).to include("[ERROR]")
      expect(summary).to include("Missing table: glyf")
      expect(summary).to include("[WARN]")
      expect(summary).to include("Checksum mismatch")
    end

    it "includes location information when present" do
      report.add_error("tables", "Missing table", "glyf table")

      summary = report.text_summary
      expect(summary).to include("(glyf table)")
    end

    it "handles missing location information" do
      report.add_error("tables", "Missing table", nil)

      summary = report.text_summary
      expect(summary).not_to include("()")
    end
  end

  describe "serialization" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: false).tap do |r|
        r.add_error("tables", "Missing table: glyf", nil)
        r.add_warning("checksum", "Checksum mismatch", "head table")
        r.add_info("optimization", "Could benefit from subsetting", nil)
      end
    end

    it "serializes to YAML" do
      yaml = report.to_yaml

      expect(yaml).to include("font_path: test.ttf")
      expect(yaml).to include("valid: false")
      # Summary and issues serialization depends on Lutaml::Model behavior
      # The core fields are present
    end

    it "serializes to JSON" do
      json = report.to_json

      expect(json).to include('"font_path":"test.ttf"')
      expect(json).to include('"valid":false')
      # Summary and issues serialization depends on Lutaml::Model behavior
      # The core fields are present
    end
  end

  describe "issue creation" do
    let(:report) do
      described_class.new(font_path: "test.ttf", valid: true)
    end

    it "maintains issue order" do
      report.add_error("tables", "Error 1", nil)
      report.add_warning("checksum", "Warning 1", nil)
      report.add_error("structure", "Error 2", nil)
      report.add_info("optimization", "Info 1", nil)

      expect(report.issues[0].message).to eq("Error 1")
      expect(report.issues[1].message).to eq("Warning 1")
      expect(report.issues[2].message).to eq("Error 2")
      expect(report.issues[3].message).to eq("Info 1")
    end

    it "updates summary counts correctly" do
      report.add_error("tables", "Error 1", nil)
      report.add_error("tables", "Error 2", nil)
      report.add_warning("checksum", "Warning 1", nil)
      report.add_info("optimization", "Info 1", nil)

      expect(report.summary.errors).to eq(2)
      expect(report.summary.warnings).to eq(1)
      expect(report.summary.info).to eq(1)
    end
  end
end
