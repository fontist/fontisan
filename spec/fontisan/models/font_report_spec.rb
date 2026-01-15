# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::FontReport do
  let(:validation_report) do
    Fontisan::Models::ValidationReport.new(
      font_path: "test.ttf",
      valid: true,
    )
  end

  describe "#initialize" do
    it "creates a font report with index and name" do
      report = described_class.new(
        font_index: 0,
        font_name: "Test Font",
        report: validation_report,
      )

      expect(report.font_index).to eq(0)
      expect(report.font_name).to eq("Test Font")
      expect(report.report).to eq(validation_report)
    end
  end
end
