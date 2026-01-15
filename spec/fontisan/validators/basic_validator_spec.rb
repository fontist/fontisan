# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Validators::BasicValidator do
  let(:validator) { described_class.new }

  # Use real fonts with known characteristics
  let(:valid_font_path) { fixture_path("fonttools/TestTTF.ttf") }
  let(:valid_font) { Fontisan::FontLoader.load(valid_font_path) }

  # Rupali has name table issues (known from ftxvalidator)
  let(:rupali_font_path) { fixture_path("fonts/Rupali/Rupali_0.72.ttf") }
  let(:rupali_font) { Fontisan::FontLoader.load(rupali_font_path) }

  # Siyam Rupali has sbit issues (known from ftxvalidator)
  let(:siyam_font_path) do
    fixture_path("fonts/SiyamRupaliANSI/Siyam Rupali ANSI.ttf")
  end
  let(:siyam_font) { Fontisan::FontLoader.load(siyam_font_path) }

  describe "#validate" do
    context "with a valid font" do
      it "returns a valid report" do
        report = validator.validate(valid_font)

        expect(report).to be_a(Fontisan::Models::ValidationReport)
        expect(report.valid?).to be true
        expect(report.status).to eq("valid")
      end

      it "performs all 8 checks" do
        report = validator.validate(valid_font)

        expect(report.checks_performed.length).to eq(8)
        expect(report.checks_performed).to include(
          "required_tables",
          "name_version",
          "family_name",
          "postscript_name",
          "head_magic",
          "units_per_em",
          "num_glyphs",
          "reasonable_metrics",
        )
      end

      it "has all checks passing" do
        report = validator.validate(valid_font)

        expect(report.passed_checks.length).to eq(8)
        expect(report.failed_checks).to be_empty
      end

      it "completes in < 50ms" do
        # Warm up
        validator.validate(valid_font)

        # Measure
        start_time = Time.now
        validator.validate(valid_font)
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.05 # 50ms
      end
    end

    context "required_tables check" do
      it "passes when all required tables present" do
        report = validator.validate(valid_font)
        result = report.result_of(:required_tables)

        expect(result.passed).to be true
      end

      it "fails when a required table is missing" do
        # Mock a font with missing table
        allow(valid_font).to receive(:table).and_call_original
        allow(valid_font).to receive(:table).with("name").and_return(nil)

        report = validator.validate(valid_font)
        result = report.result_of(:required_tables)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "name_version check" do
      it "passes for version 0" do
        report = validator.validate(valid_font)
        result = report.result_of(:name_version)

        expect(result.passed).to be true
      end

      it "fails for invalid version" do
        name_table = valid_font.table("name")
        allow(name_table).to receive(:valid_version?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:name_version)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "family_name check" do
      it "passes when family name is present" do
        report = validator.validate(valid_font)
        result = report.result_of(:family_name)

        expect(result.passed).to be true
      end

      it "fails when family name is missing" do
        name_table = valid_font.table("name")
        allow(name_table).to receive(:family_name_present?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:family_name)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "postscript_name check" do
      it "passes when PostScript name is valid" do
        report = validator.validate(valid_font)
        result = report.result_of(:postscript_name)

        expect(result.passed).to be true
      end

      it "fails when PostScript name is invalid" do
        name_table = valid_font.table("name")
        allow(name_table).to receive(:postscript_name_valid?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:postscript_name)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "head_magic check" do
      it "passes when magic number is correct" do
        report = validator.validate(valid_font)
        result = report.result_of(:head_magic)

        expect(result.passed).to be true
      end

      it "fails when magic number is incorrect" do
        head_table = valid_font.table("head")
        allow(head_table).to receive(:valid_magic?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:head_magic)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "units_per_em check" do
      it "passes when units per em is valid" do
        report = validator.validate(valid_font)
        result = report.result_of(:units_per_em)

        expect(result.passed).to be true
      end

      it "fails when units per em is invalid" do
        head_table = valid_font.table("head")
        allow(head_table).to receive(:valid_units_per_em?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:units_per_em)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "num_glyphs check" do
      it "passes when num_glyphs is at least 1" do
        report = validator.validate(valid_font)
        result = report.result_of(:num_glyphs)

        expect(result.passed).to be true
      end

      it "fails when num_glyphs is invalid" do
        maxp_table = valid_font.table("maxp")
        allow(maxp_table).to receive(:valid_num_glyphs?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:num_glyphs)

        expect(result.passed).to be false
        expect(result.severity).to eq("error")
      end
    end

    context "reasonable_metrics check" do
      it "passes when metrics are reasonable" do
        report = validator.validate(valid_font)
        result = report.result_of(:reasonable_metrics)

        expect(result.passed).to be true
      end

      it "is a warning level check" do
        maxp_table = valid_font.table("maxp")
        allow(maxp_table).to receive(:reasonable_metrics?).and_return(false)

        report = validator.validate(valid_font)
        result = report.result_of(:reasonable_metrics)

        expect(result.severity).to eq("warning")
      end
    end

    context "validation report structure" do
      let(:report) { validator.validate(valid_font) }

      it "includes font path" do
        # Font objects may not store the original file path
        # The validator correctly handles this by using "unknown" as fallback
        expect(report.font_path).to be_a(String)
        expect(report.font_path.length).to be > 0
      end

      it "includes all check results" do
        expect(report.check_results.length).to eq(8)
        report.check_results.each do |check_result|
          expect(check_result).to be_a(Fontisan::Models::ValidationReport::CheckResult)
          expect(check_result.check_id).to be_a(String)
          expect([true, false]).to include(check_result.passed)
          expect(check_result.severity).to be_a(String)
        end
      end

      it "has proper summary counts" do
        expect(report.summary).to be_a(Fontisan::Models::ValidationReport::Summary)
        expect(report.summary.errors).to eq(0)
        expect(report.summary.warnings).to eq(0)
        expect(report.summary.info).to eq(0)
      end
    end

    context "error reporting" do
      it "adds errors to report for failed error-level checks" do
        # Mock multiple failures
        allow(valid_font).to receive(:table).and_call_original
        allow(valid_font).to receive(:table).with("name").and_return(nil)

        report = validator.validate(valid_font)

        expect(report.valid?).to be false
        expect(report.summary.errors).to be > 0
        expect(report.errors).not_to be_empty
      end

      it "adds warnings for failed warning-level checks" do
        maxp_table = valid_font.table("maxp")
        allow(maxp_table).to receive(:reasonable_metrics?).and_return(false)

        report = validator.validate(valid_font)

        expect(report.summary.warnings).to eq(1)
        expect(report.warnings.length).to eq(1)
      end
    end

    context "use case: font indexing" do
      it "validates multiple fonts quickly" do
        fonts = [
          Fontisan::FontLoader.load(fixture_path("fonttools/TestTTF.ttf")),
          Fontisan::FontLoader.load(fixture_path("fonttools/TestOTF.otf")),
        ]

        start_time = Time.now
        reports = fonts.map { |font| validator.validate(font) }
        elapsed = Time.now - start_time

        expect(reports.all?(&:valid?)).to be true
        expect(elapsed).to be < 0.1 # < 100ms for 2 fonts
      end
    end
  end
end
