# frozen_string_literal: true

require "spec_helper"
require "fontisan/formatters"
require "fontisan/models/audit"

RSpec.describe Fontisan::Formatters::LibrarySummaryTextRenderer do
  def render(summary)
    described_class.new(summary).render
  end

  it "prints the header with root, files, and face counts" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 3, total_faces: 5,
      scanned_extensions: %w[.ttf .ttc]
    )
    out = render(summary)
    expect(out).to include("LIBRARY SUMMARY")
    expect(out).to include("root:    /lib")
    expect(out).to include("files:   3   faces: 5")
    expect(out).to include("formats: .ttf, .ttc")
  end

  it "prints aggregate metrics including a human-readable total size" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 1, total_faces: 1,
      aggregate_metrics: { total_codepoints: 1000, total_glyphs: 1200,
                           total_size_bytes: 2_097_152 }
    )
    out = render(summary)
    expect(out).to include("AGGREGATES")
    expect(out).to include("codepoints:     1000")
    expect(out).to include("glyphs:         1200")
    expect(out).to include("total size:     2.0 MB")
  end

  it "lists script coverage rows sorted by face count" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 2, total_faces: 2,
      script_coverage: [
        Fontisan::Models::Audit::ScriptCoverageRow.new(
          script: "Latin", face_count: 2, faces: %w[A B],
        ),
        Fontisan::Models::Audit::ScriptCoverageRow.new(
          script: "Greek", face_count: 1, faces: ["A"],
        ),
      ]
    )
    out = render(summary)
    expect(out).to include("Latin: 2 faces")
    expect(out).to include("Greek: 1 face")
  end

  it "lists each duplicate group with sha prefix and file paths" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 2, total_faces: 2,
      duplicate_groups: [
        Fontisan::Models::Audit::DuplicateGroup.new(
          source_sha256: "abc123def456", files: ["/lib/a.ttf", "/lib/b.ttf"],
        ),
      ]
    )
    out = render(summary)
    expect(out).to include("DUPLICATES (1 group)")
    expect(out).to include("sha abc123def456:")
    expect(out).to include("/lib/a.ttf")
    expect(out).to include("/lib/b.ttf")
  end

  it "lists license distribution sorted by count descending" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 3, total_faces: 3,
      license_distribution: {
        "https://ofl.org" => 2, "(none)" => 1
      }
    )
    out = render(summary)
    expect(out).to include("LICENSE DISTRIBUTION")
    expect(out).to include("2  https://ofl.org")
    expect(out).to include("1  (none)")
  end

  it "omits the duplicate / license / script sections when empty" do
    summary = Fontisan::Models::Audit::LibrarySummary.new(
      root_path: "/lib", total_files: 0, total_faces: 0,
    )
    out = render(summary)
    expect(out).not_to include("DUPLICATES")
    expect(out).not_to include("LICENSE DISTRIBUTION")
    expect(out).not_to include("SCRIPT COVERAGE")
  end
end
