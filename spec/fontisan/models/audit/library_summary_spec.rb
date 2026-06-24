# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::LibrarySummary do
  let(:report_a) do
    Fontisan::Models::Audit::AuditReport.new(
      font_index: 0, num_fonts_in_source: 1,
      family_name: "NotoSans", postscript_name: "NotoSans-Regular",
      source_file: "/lib/a.ttf", source_sha256: "abc",
      total_codepoints: 100, total_glyphs: 110
    )
  end

  let(:row) do
    Fontisan::Models::Audit::ScriptCoverageRow.new(
      script: "Latin", face_count: 1, faces: ["NotoSans-Regular"],
    )
  end

  let(:dup) do
    Fontisan::Models::Audit::DuplicateGroup.new(
      source_sha256: "abc", files: ["/lib/a.ttf", "/lib/b.ttf"],
    )
  end

  let(:summary) do
    described_class.new(
      root_path: "/lib",
      total_files: 2,
      total_faces: 2,
      scanned_extensions: [".ttf"],
      aggregate_metrics: { total_codepoints: 200, total_glyphs: 220 },
      script_coverage: [row],
      duplicate_groups: [dup],
      license_distribution: { "https://open.com" => 2 },
      per_face_reports: [report_a],
    )
  end

  it "exposes the scalar rollup fields" do
    expect(summary.root_path).to eq("/lib")
    expect(summary.total_files).to eq(2)
    expect(summary.total_faces).to eq(2)
    expect(summary.scanned_extensions).to eq([".ttf"])
  end

  it "exposes the nested collections by their model types" do
    expect(summary.script_coverage.first).to be_a(Fontisan::Models::Audit::ScriptCoverageRow)
    expect(summary.duplicate_groups.first).to be_a(Fontisan::Models::Audit::DuplicateGroup)
    expect(summary.per_face_reports.first).to be_a(Fontisan::Models::Audit::AuditReport)
  end

  it "exposes the aggregate hashes" do
    expect(summary.aggregate_metrics[:total_codepoints]).to eq(200)
    expect(summary.license_distribution["https://open.com"]).to eq(2)
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(summary.to_yaml)
    expect(restored.root_path).to eq("/lib")
    expect(restored.total_faces).to eq(2)
    expect(restored.script_coverage.first.script).to eq("Latin")
    expect(restored.duplicate_groups.first.files).to eq(["/lib/a.ttf", "/lib/b.ttf"])
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(summary.to_json)
    expect(restored.total_files).to eq(2)
    expect(restored.per_face_reports.first.postscript_name).to eq("NotoSans-Regular")
  end
end
