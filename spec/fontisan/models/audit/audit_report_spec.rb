# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::AuditReport do
  let(:report) do
    described_class.new(
      generated_at: "2025-01-01T00:00:00Z",
      fontisan_version: "0.1.0",
      source_file: "/tmp/font.ttf",
      source_sha256: "abc123",
      source_format: "ttf",
      font_index: 0,
      num_fonts_in_source: 1,
      family_name: "NotoSans",
      subfamily_name: "Regular",
      full_name: "NotoSans Regular",
      postscript_name: "NotoSans-Regular",
      version: "Version 2.0",
      font_revision: 2.0,
      weight_class: 400,
      width_class: 5,
      italic: false,
      bold: false,
      panose: "2 0 5 3 0 0 0 0 0 0",
      is_variable: false,
      axes: [],
      total_codepoints: 128,
      total_glyphs: 256,
      cmap_subtables: [4, 12],
      codepoints: ["U+0041"],
      ucd_version: "17.0.0",
      blocks: [],
      unicode_scripts: ["Latin"],
      opentype_scripts: ["latn"],
      features: ["kern"],
      warning: nil,
    )
  end

  describe "attribute access" do
    it "exposes all set fields" do
      expect(report.family_name).to eq("NotoSans")
      expect(report.weight_class).to eq(400)
      expect(report.is_variable).to be false
      expect(report.total_glyphs).to eq(256)
      expect(report.cmap_subtables).to eq([4, 12])
      expect(report.unicode_scripts).to eq(["Latin"])
    end

    it "defaults unspecified fields to nil" do
      empty = described_class.new
      expect(empty.family_name).to be_nil
      expect(empty.blocks).to be_nil
      expect(empty.codepoints).to be_nil
    end
  end

  describe "YAML round-trip" do
    it "round-trips through to_yaml / from_yaml" do
      yaml = report.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.family_name).to eq("NotoSans")
      expect(restored.weight_class).to eq(400)
      expect(restored.source_sha256).to eq("abc123")
      expect(restored.cmap_subtables).to eq([4, 12])
      expect(restored.is_variable).to be false
    end
  end

  describe "JSON round-trip" do
    it "round-trips through to_json / from_json" do
      json = report.to_json
      restored = described_class.from_json(json)

      expect(restored.postscript_name).to eq("NotoSans-Regular")
      expect(restored.italic).to be false
      expect(restored.total_codepoints).to eq(128)
    end
  end

  describe "nested AuditBlock collection" do
    it "serializes blocks as nested models" do
      block = Fontisan::Models::Audit::AuditBlock.new(
        name: "Basic Latin",
        first_cp: 0x0000,
        last_cp: 0x007F,
        range: "U+0000-U+007F",
        total: 128,
        covered: 26,
        fill_ratio: 0.2031,
        complete: false,
      )
      report.blocks = [block]

      yaml = report.to_yaml
      restored = described_class.from_yaml(yaml)
      expect(restored.blocks.first).to be_a(Fontisan::Models::Audit::AuditBlock)
      expect(restored.blocks.first.name).to eq("Basic Latin")
      expect(restored.blocks.first.covered).to eq(26)
    end
  end

  describe "nested AuditAxis collection" do
    it "serializes axes as nested models" do
      axis = Fontisan::Models::Audit::AuditAxis.new(
        tag: "wght",
        min_value: 100.0,
        default_value: 400.0,
        max_value: 900.0,
        name: "Weight",
      )
      report.axes = [axis]

      yaml = report.to_yaml
      restored = described_class.from_yaml(yaml)
      expect(restored.axes.first).to be_a(Fontisan::Models::Audit::AuditAxis)
      expect(restored.axes.first.tag).to eq("wght")
      expect(restored.axes.first.default_value).to eq(400.0)
    end
  end
end
