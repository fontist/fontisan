# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::CollectionValidationReport do
  describe "#initialize" do
    it "creates a collection report with metadata" do
      report = described_class.new(
        collection_path: "/path/to/font.ttc",
        collection_type: "TTC",
        num_fonts: 2,
      )

      expect(report.collection_path).to eq("/path/to/font.ttc")
      expect(report.collection_type).to eq("TTC")
      expect(report.num_fonts).to eq(2)
      expect(report.font_reports).to eq([])
    end
  end

  describe "#add_font_report" do
    it "adds a font report to the collection" do
      collection_report = described_class.new(
        collection_path: "/path/to/font.ttc",
        collection_type: "TTC",
        num_fonts: 2,
      )

      validation_report = Fontisan::Models::ValidationReport.new(
        font_path: "font.ttf",
        valid: true,
      )

      font_report = Fontisan::Models::FontReport.new(
        font_index: 0,
        font_name: "Test Font",
        report: validation_report,
      )

      collection_report.font_reports << font_report

      expect(collection_report.font_reports.length).to eq(1)
      expect(collection_report.font_reports.first.font_index).to eq(0)
    end
  end

  describe "#overall_status" do
    context "when all fonts are valid" do
      it "returns 'valid'" do
        report = described_class.new(
          collection_path: "/path/to/font.ttc",
          collection_type: "TTC",
          num_fonts: 2,
        )

        valid_report1 = Fontisan::Models::ValidationReport.new(
          font_path: "f1.ttf", valid: true,
        )
        valid_report2 = Fontisan::Models::ValidationReport.new(
          font_path: "f2.ttf", valid: true,
        )

        report.font_reports << Fontisan::Models::FontReport.new(font_index: 0,
                                                                font_name: "F1", report: valid_report1)
        report.font_reports << Fontisan::Models::FontReport.new(font_index: 1,
                                                                font_name: "F2", report: valid_report2)

        expect(report.overall_status).to eq("valid")
      end
    end

    context "when any font has errors" do
      it "returns 'invalid'" do
        report = described_class.new(
          collection_path: "/path/to/font.ttc",
          collection_type: "TTC",
          num_fonts: 2,
        )

        valid_report = Fontisan::Models::ValidationReport.new(
          font_path: "f1.ttf", valid: true,
        )
        invalid_report = Fontisan::Models::ValidationReport.new(
          font_path: "f2.ttf", valid: false,
        )
        invalid_report.add_error("test", "test error", nil)

        report.font_reports << Fontisan::Models::FontReport.new(font_index: 0,
                                                                font_name: "F1", report: valid_report)
        report.font_reports << Fontisan::Models::FontReport.new(font_index: 1,
                                                                font_name: "F2", report: invalid_report)

        expect(report.overall_status).to eq("invalid")
      end
    end

    context "when fonts have warnings but no errors" do
      it "returns 'valid_with_warnings'" do
        report = described_class.new(
          collection_path: "/path/to/font.ttc",
          collection_type: "TTC",
          num_fonts: 2,
        )

        valid_report = Fontisan::Models::ValidationReport.new(
          font_path: "f1.ttf", valid: true,
        )
        warning_report = Fontisan::Models::ValidationReport.new(
          font_path: "f2.ttf", valid: true,
        )
        warning_report.add_warning("test", "test warning", nil)

        report.font_reports << Fontisan::Models::FontReport.new(font_index: 0,
                                                                font_name: "F1", report: valid_report)
        report.font_reports << Fontisan::Models::FontReport.new(font_index: 1,
                                                                font_name: "F2", report: warning_report)

        expect(report.overall_status).to eq("valid_with_warnings")
      end
    end
  end

  describe "#text_summary" do
    it "returns formatted output with collection header and per-font sections" do
      report = described_class.new(
        collection_path: "/path/to/font.ttc",
        collection_type: "TrueType Collection",
        num_fonts: 2
      )

      valid_report = Fontisan::Models::ValidationReport.new(font_path: "f1.ttf", valid: true)
      invalid_report = Fontisan::Models::ValidationReport.new(font_path: "f2.ttf", valid: false)
      invalid_report.add_error("glyphs", "test error", nil)

      report.font_reports << Fontisan::Models::FontReport.new(font_index: 0, font_name: "Font One", report: valid_report)
      report.font_reports << Fontisan::Models::FontReport.new(font_index: 1, font_name: "Font Two", report: invalid_report)

      output = report.text_summary

      expect(output).to include("Collection: /path/to/font.ttc")
      expect(output).to include("Type: TrueType Collection")
      expect(output).to include("Fonts: 2")
      expect(output).to include("=== Font 0: Font One ===")
      expect(output).to include("=== Font 1: Font Two ===")
    end
  end
end
