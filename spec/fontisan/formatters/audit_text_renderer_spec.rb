# frozen_string_literal: true

require "spec_helper"
require "fontisan/formatters"
require "fontisan/models/audit"

RSpec.describe Fontisan::Formatters::AuditTextRenderer do
  def report(overrides = {})
    Fontisan::Models::Audit::AuditReport.new(
      generated_at: "2026-06-24T14:03:50Z",
      fontisan_version: "0.2.20",
      source_file: "/lib/Foo-Regular.ttf",
      source_sha256: "abc123",
      source_format: "ttf",
      font_index: 0, num_fonts_in_source: 1,
      family_name: "Foo", subfamily_name: "Regular",
      full_name: "Foo Regular", postscript_name: "Foo-Regular",
      version: "Version 1.0", font_revision: 1.0,
      weight_class: 700, width_class: 5, bold: false, italic: false,
      panose: "0 0 0 0 0 0 0 0 0 0",
      total_codepoints: 100, total_glyphs: 110,
      cmap_subtables: [4, 12],
      **overrides
    )
  end

  def render(report)
    described_class.new(report).render
  end

  it "uses postscript_name as the title" do
    expect(render(report).lines.first.chomp).to eq("Foo-Regular")
  end

  it "includes the provenance block in the header" do
    out = render(report)
    expect(out).to include("source_sha256: abc123")
    expect(out).to include("source_file:   /lib/Foo-Regular.ttf")
    expect(out).to include("source_format: ttf")
    expect(out).to include("layout: single face (1/1)")
  end

  it "reports collection-face layout when num_fonts_in_source > 1" do
    out = render(report(font_index: 2, num_fonts_in_source: 4))
    expect(out).to include("layout: collection face (3/4)")
  end

  it "annotates weight class with its conventional name" do
    expect(render(report)).to include("Weight class:     700 (Bold)")
  end

  it "annotates width class with its conventional name" do
    expect(render(report)).to include("Width class:      5 (Medium)")
  end

  it "renders metrics when present" do
    metrics = Fontisan::Models::Audit::Metrics.new(
      units_per_em: 1000, hhea_ascent: 800, hhea_descent: -200, hhea_line_gap: 0,
      bbox_x_min: -100, bbox_y_min: -200, bbox_x_max: 1100, bbox_y_max: 900,
      x_height: 500, cap_height: 700
    )
    out = render(report(metrics: metrics))
    expect(out).to include("METRICS")
    expect(out).to include("unitsPerEm:       1000")
    expect(out).to include("bbox:")
  end

  it "skips the METRICS section when metrics is nil" do
    expect(render(report)).not_to include("METRICS")
  end

  it "renders hinting when present" do
    hinting = Fontisan::Models::Audit::Hinting.new(
      hinting_format: "truetype",
      has_fpgm: true, fpgm_instruction_count: 64,
      has_prep: true, prep_instruction_count: 32,
      has_cvt: true, cvt_entry_count: 16
    )
    out = render(report(hinting: hinting))
    expect(out).to include("Format:           truetype")
    expect(out).to include("fpgm:             64 instructions")
    expect(out).to include("cvt:              16 entries")
  end

  it "renders VARIABLE FONT section as '(not variable)' without axes" do
    expect(render(report)).to include("VARIABLE FONT").and include("(not variable)")
  end

  it "renders axes when variation is present" do
    axis = Fontisan::Models::Audit::AuditAxis.new(
      tag: "wght", min_value: 100.0, default_value: 400.0, max_value: 900.0,
    )
    variation = Fontisan::Models::Audit::VariationDetail.new(axes: [axis])
    out = render(report(variation: variation))
    expect(out).to include("wght:")
    expect(out).to include("100.0 .. 900.0")
  end

  it "truncates long feature lists with an ellipsis" do
    layout = Fontisan::Models::Audit::OpenTypeLayout.new(
      scripts: %w[latn], features: %w[a b c d e f g h i j k l],
      has_gsub: true, has_gpos: true
    )
    out = render(report(opentype_layout: layout))
    expect(out).to include("Features (12)")
    expect(out).to include("...")
  end

  it "truncates long codepoint range lists" do
    ranges = (1..15).map do |i|
      Fontisan::Models::Audit::CodepointRange.new(first_cp: i, last_cp: i)
    end
    out = render(report(codepoint_ranges: ranges))
    expect(out).to include("Ranges (top 10):")
    expect(out).to include("...")
  end

  it "renders WARNINGS as (none) when warning is nil" do
    expect(render(report)).to include("WARNINGS").and include("(none)")
  end

  it "renders the warning text when set" do
    expect(render(report(warning: "UCD download failed"))).to include("UCD download failed")
  end

  it "does not crash on a bare-minimum Type 1 report (all sub-models nil)" do
    minimal = Fontisan::Models::Audit::AuditReport.new(
      font_index: 0, num_fonts_in_source: 1, postscript_name: "BareType1",
    )
    expect { render(minimal) }.not_to raise_error
    expect(render(minimal)).to include("BareType1")
  end
end
