# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Audit validation checks" do
  let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe Fontisan::Audit::Checks::TableDirectoryCheck do
    it ".code returns :table_directory" do
      expect(described_class.code).to eq(:table_directory)
    end

    it "returns no issues for a well-formed font" do
      issues = described_class.call(font)
      expect(issues).to all(satisfy { |i| i.is_a?(Fontisan::Models::ValidationReport::Issue) })
      error_issues = issues.select { |i| i.severity == "error" }
      expect(error_issues).to be_empty
    end

    it "every issue has the correct category" do
      issues = described_class.call(font)
      issues.each do |i|
        expect(i.category).to eq("table_directory")
      end
    end
  end

  describe Fontisan::Audit::Checks::GlyphNameCheck do
    it ".code returns :glyph_names" do
      expect(described_class.code).to eq(:glyph_names)
    end

    it "returns no error-level issues for a well-formed font" do
      issues = described_class.call(font)
      errors = issues.select { |i| i.severity == "error" }
      expect(errors).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::CmapCheck do
    it ".code returns :cmap" do
      expect(described_class.code).to eq(:cmap)
    end

    it "returns no issues for a well-formed font" do
      issues = described_class.call(font)
      expect(issues).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::OtsCompatibilityCheck do
    it ".code returns :ots_compatibility" do
      expect(described_class.code).to eq(:ots_compatibility)
    end

    it "returns no error-level issues for a well-formed font" do
      issues = described_class.call(font)
      errors = issues.select { |i| i.severity == "error" }
      expect(errors).to be_empty
    end
  end

  describe Fontisan::Audit::Checks::CollectionIntegrityCheck do
    it ".code returns :collection_integrity" do
      expect(described_class.code).to eq(:collection_integrity)
    end

    it "returns empty for a non-collection (single font)" do
      issues = described_class.call(font)
      expect(issues).to be_empty
    end
  end

  describe Fontisan::Audit::CheckRegistry do
    it ".for(:default) returns all check classes" do
      checks = described_class.for(:default)
      expect(checks).to include(Fontisan::Audit::Checks::TableDirectoryCheck)
      expect(checks).to include(Fontisan::Audit::Checks::GlyphNameCheck)
      expect(checks).to include(Fontisan::Audit::Checks::CmapCheck)
      expect(checks).to include(Fontisan::Audit::Checks::OtsCompatibilityCheck)
      expect(checks).to include(Fontisan::Audit::Checks::CollectionIntegrityCheck)
    end

    it ".for(:ots) returns only OTS compatibility check" do
      checks = described_class.for(:ots)
      expect(checks).to eq([Fontisan::Audit::Checks::OtsCompatibilityCheck])
    end

    it ".for(:structural) returns directory + collection + conformance checks" do
      checks = described_class.for(:structural)
      expect(checks).to contain_exactly(
        Fontisan::Audit::Checks::TableDirectoryCheck,
        Fontisan::Audit::Checks::CollectionIntegrityCheck,
        Fontisan::Audit::Checks::OpenTypeConformanceCheck,
      )
    end

    it ".for(:layout) returns glyph name + cmap + ot_layout checks" do
      checks = described_class.for(:layout)
      expect(checks).to contain_exactly(
        Fontisan::Audit::Checks::GlyphNameCheck,
        Fontisan::Audit::Checks::CmapCheck,
        Fontisan::Audit::Checks::LayoutTableCheck,
      )
    end

    it "falls back to :default for unknown profiles" do
      expect(described_class.for(:nonexistent)).to eq(described_class.for(:default))
    end
  end

  describe "integration with AuditCommand" do
    it "runs validation when validate: true" do
      cmd = Fontisan::Commands::AuditCommand.new(
        font_path, include_codepoints: false, validate: true
      )
      report = cmd.run
      expect(report.validation_issues).to be_an(Array)
    end

    it "skips validation when validate is not set" do
      cmd = Fontisan::Commands::AuditCommand.new(
        font_path, include_codepoints: false
      )
      report = cmd.run
      expect(report.validation_issues).to be_empty.or be_nil
    end

    it "supports profile-based validation" do
      cmd = Fontisan::Commands::AuditCommand.new(
        font_path, include_codepoints: false, validate: :ots
      )
      report = cmd.run
      expect(report.validation_issues).to be_an(Array)
    end
  end
end
