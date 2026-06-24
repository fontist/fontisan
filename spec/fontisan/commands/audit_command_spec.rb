# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/audit_command"
require "fontisan/ucd/cache_manager"
require "fontisan/ucd/index_builder"
require "tmpdir"

RSpec.describe Fontisan::Commands::AuditCommand do
  # Pre-populate a tiny UCD cache so specs don't hit the network.
  # The fixture covers Basic Latin + Latin-1 Supplement + a couple of Greek
  # codepoints — enough to exercise aggregate_blocks / aggregate_scripts
  # against real fixtures.
  let(:ucd_xml) do
    <<~XML
      <ucd>
        <char cp="0041" name="LATIN CAPITAL LETTER A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
        <char cp="0042" name="LATIN CAPITAL LETTER B" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
        <char cp="0061" name="LATIN SMALL LETTER A" general-category="Ll" script="Latin" block="Basic Latin" age="1.1"/>
        <char first-cp="0080" last-cp="00FF" name="LATIN-1 SUPPLEMENT RANGE" general-category="So" script="Latin" block="Latin-1 Supplement" age="1.1"/>
        <char cp="0391" name="GREEK CAPITAL LETTER ALPHA" general-category="Lu" script="Greek" block="Greek and Coptic" age="1.1"/>
      </ucd>
    XML
  end
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:ttc_path) do
    font_fixture_path("DinaRemasterII", "DinaRemasterII.ttc")
  end

  around do |example|
    Dir.mktmpdir do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir

      # Populate cache for known version 17.0.0
      version = "17.0.0"
      Fontisan::Ucd::CacheManager.ensure_version_dir!(version)
      File.write(Fontisan::Ucd::CacheManager.ucdxml_path(version), ucd_xml)
      Fontisan::Ucd::IndexBuilder.build(version)

      example.run
    ensure
      ENV["XDG_CONFIG_HOME"] = original_xdg
    end
  end

  describe "#run with a single font" do
    it "returns a single AuditReport" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      result = cmd.run

      expect(result).to be_a(Fontisan::Models::Audit::AuditReport)
    end

    it "populates provenance fields" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.source_file).to eq(File.expand_path(ttf_path))
      expect(report.source_sha256).to match(/\A[0-9a-f]{64}\z/)
      expect(report.source_format).to eq("ttf")
      expect(report.fontisan_version).to eq(Fontisan::VERSION)
      expect(report.generated_at).not_to be_nil
    end

    it "populates identity from name table" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.family_name).not_to be_nil
      expect(report.postscript_name).not_to be_nil
    end

    it "populates style from OS/2 + head" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.weight_class).to be_an(Integer)
      expect(report.panose).to match(/\A(\d+ ){9}\d+\z/)
    end

    it "populates coverage counts" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.total_codepoints).to be > 0
      expect(report.total_glyphs).to be > 0
      expect(report.cmap_subtables).to be_an(Array)
      expect(report.cmap_subtables).not_to be_empty
    end

    it "populates OpenType layout summary" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.opentype_layout).to be_a(Fontisan::Models::Audit::OpenTypeLayout)
      expect(report.opentype_layout.scripts).to be_an(Array)
      expect(report.opentype_layout.features).to be_an(Array)
    end

    it "sets source layout to single face" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.font_index).to eq(0)
      expect(report.num_fonts_in_source).to eq(1)
    end

    it "aggregates against cached UCD without a warning" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.warning).to be_nil
      expect(report.ucd_version).to eq("17.0.0")
      expect(report.blocks).to be_an(Array)
      expect(report.unicode_scripts).to include("Latin")
    end

    it "populates codepoint_ranges by default with empty codepoints list" do
      cmd = described_class.new(ttf_path, ucd_version: "17.0.0")
      report = cmd.run

      expect(report.codepoint_ranges).to be_an(Array)
      expect(report.codepoint_ranges).not_to be_empty
      expect(report.codepoint_ranges.first).to be_a(Fontisan::Models::Audit::CodepointRange)
      expect(report.codepoints).to eq([])
      expect(report.total_codepoints).to be > 0
    end

    it "honors :all_codepoints to populate the per-codepoint list" do
      cmd = described_class.new(ttf_path, all_codepoints: true,
                                          ucd_version: "17.0.0")
      report = cmd.run

      expect(report.codepoints.first).to match(/\AU\+[0-9A-F]{4,6}\z/)
      expect(report.codepoints.length).to eq(report.total_codepoints)
    end

    it "records a warning when UCD version is unknown" do
      cmd = described_class.new(ttf_path, ucd_version: "0.0.0-never")
      report = cmd.run

      expect(report.warning).to match(/UCD version rejected|not recognized/)
      expect(report.blocks).to eq([])
      expect(report.ucd_version).to be_nil
    end
  end

  describe "#run with a collection" do
    it "returns an array of AuditReports" do
      cmd = described_class.new(ttc_path, ucd_version: "17.0.0")
      reports = cmd.run

      expect(reports).to be_an(Array)
      expect(reports.length).to be > 1
      expect(reports).to all(be_a(Fontisan::Models::Audit::AuditReport))
    end

    it "records correct font_index for each face" do
      cmd = described_class.new(ttc_path, ucd_version: "17.0.0")
      reports = cmd.run

      indices = reports.map(&:font_index)
      expect(indices).to eq((0...reports.length).to_a)
    end

    it "records num_fonts_in_source matching report count" do
      cmd = described_class.new(ttc_path, ucd_version: "17.0.0")
      reports = cmd.run

      expect(reports.first.num_fonts_in_source).to eq(reports.length)
    end
  end

  describe ".write_reports" do
    let(:report) do
      Fontisan::Models::Audit::AuditReport.new(
        font_index: 0,
        num_fonts_in_source: 1,
        postscript_name: "NotoSans-Regular",
        family_name: "NotoSans",
      )
    end

    it "writes one file per report under the given directory" do
      paths = described_class.write_reports([report], to: Dir.mktmpdir,
                                                      format: :yaml)
      expect(paths.length).to eq(1)
      expect(File.exist?(paths.first)).to be true
      expect(File.extname(paths.first)).to eq(".yaml")
      expect(File.basename(paths.first)).to start_with("NotoSans-Regular")
    end

    it "writes JSON when format is :json" do
      paths = described_class.write_reports([report], to: Dir.mktmpdir,
                                                      format: :json)
      expect(File.extname(paths.first)).to eq(".json")
    end

    it "uses per-face filename for collection reports" do
      collection_report = Fontisan::Models::Audit::AuditReport.new(
        font_index: 3,
        num_fonts_in_source: 10,
        postscript_name: "NotoSerifCJK-Bold",
      )
      path = described_class.output_filename(collection_report, :yaml)
      expect(path).to eq("03-NotoSerifCJK-Bold.yaml")
    end

    it "sanitizes unsafe characters in filenames" do
      unsafe = Fontisan::Models::Audit::AuditReport.new(
        font_index: 0,
        num_fonts_in_source: 1,
        postscript_name: "Foo Bar/Baz",
      )
      filename = described_class.output_filename(unsafe, :yaml)
      expect(filename).to match(/\AFoo_Bar_Baz\.yaml\z/)
    end

    it "falls back to family_name when postscript_name is nil" do
      no_ps = Fontisan::Models::Audit::AuditReport.new(
        font_index: 0,
        num_fonts_in_source: 1,
        postscript_name: nil,
        family_name: "Some Family",
      )
      filename = described_class.output_filename(no_ps, :yaml)
      expect(filename).to eq("Some_Family.yaml")
    end

    it "falls back to 'font' when both names are nil" do
      blank = Fontisan::Models::Audit::AuditReport.new(
        font_index: 0,
        num_fonts_in_source: 1,
      )
      filename = described_class.output_filename(blank, :yaml)
      expect(filename).to eq("font.yaml")
    end
  end
end
