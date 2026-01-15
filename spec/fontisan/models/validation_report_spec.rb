# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::ValidationReport do
  let(:report) do
    described_class.new(
      font_path: "test.ttf",
      valid: true,
      profile: "production",
      status: "valid",
    )
  end

  describe "basic attributes" do
    it "has font_path" do
      expect(report.font_path).to eq("test.ttf")
    end

    it "has valid attribute" do
      expect(report.valid).to be true
    end

    it "has profile" do
      expect(report.profile).to eq("production")
    end

    it "has status" do
      expect(report.status).to eq("valid")
    end
  end

  describe "#add_error" do
    it "adds error to issues" do
      report.add_error("tables", "Missing table", "name")
      expect(report.issues.length).to eq(1)
      expect(report.issues.first.severity).to eq("error")
    end

    it "increments error count" do
      report.add_error("tables", "Missing table")
      expect(report.summary.errors).to eq(1)
    end

    it "sets valid to false" do
      report.add_error("tables", "Missing table")
      expect(report.valid).to be false
    end
  end

  describe "#add_warning" do
    it "adds warning to issues" do
      report.add_warning("checksum", "Checksum mismatch", "name")
      expect(report.issues.length).to eq(1)
      expect(report.issues.first.severity).to eq("warning")
    end

    it "increments warning count" do
      report.add_warning("checksum", "Checksum mismatch")
      expect(report.summary.warnings).to eq(1)
    end

    it "does not change valid status" do
      report.add_warning("checksum", "Checksum mismatch")
      expect(report.valid).to be true
    end
  end

  describe "#add_info" do
    it "adds info to issues" do
      report.add_info("metadata", "Font uses TrueType", "glyf")
      expect(report.issues.length).to eq(1)
      expect(report.issues.first.severity).to eq("info")
    end

    it "increments info count" do
      report.add_info("metadata", "Font uses TrueType")
      expect(report.summary.info).to eq(1)
    end
  end

  describe "severity filtering methods" do
    before do
      report.add_error("tables", "Error 1")
      report.add_error("structure", "Error 2")
      report.add_warning("checksum", "Warning 1")
      report.add_warning("metrics", "Warning 2")
      report.add_info("metadata", "Info 1")
    end

    describe "#issues_by_severity" do
      it "filters by error severity" do
        errors = report.issues_by_severity(:error)
        expect(errors.length).to eq(2)
        expect(errors.all? { |i| i.severity == "error" }).to be true
      end

      it "filters by warning severity" do
        warnings = report.issues_by_severity(:warning)
        expect(warnings.length).to eq(2)
        expect(warnings.all? { |i| i.severity == "warning" }).to be true
      end

      it "filters by info severity" do
        info = report.issues_by_severity(:info)
        expect(info.length).to eq(1)
        expect(info.all? { |i| i.severity == "info" }).to be true
      end
    end

    describe "#fatal_errors" do
      it "returns empty array when no fatal errors" do
        expect(report.fatal_errors).to eq([])
      end

      it "returns fatal errors when present" do
        report.issues << described_class::Issue.new(
          severity: "fatal",
          category: "critical",
          message: "Fatal error",
        )
        expect(report.fatal_errors.length).to eq(1)
      end
    end

    describe "#errors_only" do
      it "returns only error issues" do
        errors = report.errors_only
        expect(errors.length).to eq(2)
        expect(errors.all? { |i| i.severity == "error" }).to be true
      end
    end

    describe "#warnings_only" do
      it "returns only warning issues" do
        warnings = report.warnings_only
        expect(warnings.length).to eq(2)
        expect(warnings.all? { |i| i.severity == "warning" }).to be true
      end
    end

    describe "#info_only" do
      it "returns only info issues" do
        info = report.info_only
        expect(info.length).to eq(1)
        expect(info.all? { |i| i.severity == "info" }).to be true
      end
    end
  end

  describe "category filtering methods" do
    before do
      report.add_error("tables", "Table error")
      report.add_error("structure", "Structure error")
      report.add_warning("checksum", "Checksum warning")
    end

    describe "#issues_by_category" do
      it "filters by category" do
        table_issues = report.issues_by_category("tables")
        expect(table_issues.length).to eq(1)
        expect(table_issues.first.category).to eq("tables")
      end

      it "returns empty array for non-existent category" do
        expect(report.issues_by_category("nonexistent")).to eq([])
      end
    end

    describe "#table_issues" do
      before do
        report.check_results << described_class::CheckResult.new(
          check_id: "name_version",
          passed: true,
          severity: "error",
          table: "name",
        )
        report.check_results << described_class::CheckResult.new(
          check_id: "head_magic",
          passed: false,
          severity: "error",
          table: "head",
        )
      end

      it "returns check results for specific table" do
        name_results = report.table_issues("name")
        expect(name_results.length).to eq(1)
        expect(name_results.first.table).to eq("name")
      end
    end

    describe "#field_issues" do
      before do
        report.check_results << described_class::CheckResult.new(
          check_id: "family_name",
          passed: false,
          severity: "error",
          table: "name",
          field: "family_name",
        )
      end

      it "returns check results for specific field" do
        results = report.field_issues("name", "family_name")
        expect(results.length).to eq(1)
        expect(results.first.field).to eq("family_name")
      end
    end
  end

  describe "check filtering methods" do
    before do
      report.check_results << described_class::CheckResult.new(
        check_id: "check1",
        passed: true,
        severity: "error",
      )
      report.check_results << described_class::CheckResult.new(
        check_id: "check2",
        passed: false,
        severity: "error",
      )
      report.check_results << described_class::CheckResult.new(
        check_id: "check3",
        passed: false,
        severity: "warning",
      )
    end

    describe "#checks_by_status" do
      it "returns passed checks" do
        passed = report.checks_by_status(passed: true)
        expect(passed.length).to eq(1)
        expect(passed.first.check_id).to eq("check1")
      end

      it "returns failed checks" do
        failed = report.checks_by_status(passed: false)
        expect(failed.length).to eq(2)
      end
    end

    describe "#failed_check_ids" do
      it "returns array of failed check IDs" do
        ids = report.failed_check_ids
        expect(ids).to eq(["check2", "check3"])
      end
    end

    describe "#passed_check_ids" do
      it "returns array of passed check IDs" do
        ids = report.passed_check_ids
        expect(ids).to eq(["check1"])
      end
    end
  end

  describe "statistics methods" do
    before do
      5.times do |i|
        report.check_results << described_class::CheckResult.new(
          check_id: "check_#{i}",
          passed: i < 3, # 3 passed, 2 failed
          severity: "error",
        )
      end
    end

    describe "#failure_rate" do
      it "calculates failure rate" do
        expect(report.failure_rate).to eq(0.4) # 2/5 = 0.4
      end

      it "returns 0.0 for empty report" do
        empty_report = described_class.new
        expect(empty_report.failure_rate).to eq(0.0)
      end
    end

    describe "#pass_rate" do
      it "calculates pass rate" do
        expect(report.pass_rate).to eq(0.6) # 3/5 = 0.6
      end
    end

    describe "#severity_distribution" do
      before do
        report.add_error("test", "Error")
        report.add_warning("test", "Warning")
        report.add_info("test", "Info")
      end

      it "returns distribution hash" do
        dist = report.severity_distribution
        expect(dist).to be_a(Hash)
        expect(dist[:errors]).to eq(1)
        expect(dist[:warnings]).to eq(1)
        expect(dist[:info]).to eq(1)
      end
    end
  end

  describe "export format methods" do
    before do
      report.add_error("tables", "Test error")
      report.check_results << described_class::CheckResult.new(
        check_id: "test_check",
        passed: false,
        severity: "error",
        table: "name",
      )
    end

    describe "#to_text_report" do
      it "returns text summary" do
        text = report.to_text_report
        expect(text).to be_a(String)
        expect(text).to include("test.ttf")
        expect(text).to include("INVALID")
      end
    end

    describe "#to_summary" do
      it "returns brief summary" do
        summary = report.to_summary
        expect(summary).to eq("1 errors, 0 warnings, 0 info")
      end
    end

    describe "#to_table_format" do
      it "returns tabular format" do
        table = report.to_table_format
        expect(table).to be_a(String)
        expect(table).to include("CHECK_ID | STATUS | SEVERITY | TABLE")
        expect(table).to include("test_check | FAIL | error | name")
      end
    end
  end

  describe "existing convenience methods" do
    describe "#errors" do
      it "returns error issues" do
        report.add_error("test", "Error message")
        expect(report.errors.length).to eq(1)
      end
    end

    describe "#warnings" do
      it "returns warning issues" do
        report.add_warning("test", "Warning message")
        expect(report.warnings.length).to eq(1)
      end
    end

    describe "#info_issues" do
      it "returns info issues" do
        report.add_info("test", "Info message")
        expect(report.info_issues.length).to eq(1)
      end
    end

    describe "#has_errors?" do
      it "returns true when errors exist" do
        report.add_error("test", "Error")
        expect(report.has_errors?).to be true
      end

      it "returns false when no errors" do
        expect(report.has_errors?).to be false
      end
    end

    describe "#has_warnings?" do
      it "returns true when warnings exist" do
        report.add_warning("test", "Warning")
        expect(report.has_warnings?).to be true
      end

      it "returns false when no warnings" do
        expect(report.has_warnings?).to be false
      end
    end
  end

  describe "serialization" do
    it "serializes to YAML" do
      yaml = report.to_yaml
      expect(yaml).to be_a(String)
      expect(yaml).to include("font_path")
      expect(yaml).to include("valid")
    end

    it "serializes to JSON" do
      json = report.to_json
      expect(json).to be_a(String)
      expect(json).to include("font_path")
      expect(json).to include("valid")
    end
  end
end
