# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/differ"
require "fontisan/models/audit"

RSpec.describe Fontisan::Audit::Differ do
  let(:common_attrs) do
    {
      font_index: 0,
      num_fonts_in_source: 1,
      family_name: "NotoSans",
      postscript_name: "NotoSans-Regular",
      weight_class: 400,
      total_codepoints: 0,
      total_glyphs: 0,
    }
  end

  def report(overrides = {})
    Fontisan::Models::Audit::AuditReport.new(**common_attrs, **overrides)
  end

  describe "#diff with two identical reports" do
    let(:left)  { report }
    let(:right) { report }

    it "produces no field changes" do
      diff = described_class.new(left, right).diff
      expect(diff.field_changes).to eq([])
    end

    it "produces an empty codepoint delta" do
      diff = described_class.new(left, right).diff
      expect(diff.codepoints.added_count).to eq(0)
      expect(diff.codepoints.removed_count).to eq(0)
    end

    it "is empty overall" do
      diff = described_class.new(left, right).diff
      expect(diff).to be_empty
    end
  end

  describe "#diff with one scalar field changed" do
    let(:left)  { report(weight_class: 400) }
    let(:right) { report(weight_class: 700) }

    it "emits exactly one FieldChange" do
      diff = described_class.new(left, right).diff
      expect(diff.field_changes.length).to eq(1)
    end

    it "records the field name and both values" do
      change = described_class.new(left, right).diff.field_changes.first
      expect(change).to be_a(Fontisan::Models::Audit::FieldChange)
      expect(change.field).to eq("weight_class")
      expect(change.left).to eq("400")
      expect(change.right).to eq("700")
    end
  end

  describe "#diff with multiple scalar fields changed" do
    let(:left) do
      report(family_name: "NotoSans", postscript_name: "NotoSans-Regular",
             weight_class: 400)
    end
    let(:right) do
      report(family_name: "NotoSerif", postscript_name: "NotoSerif-Bold",
             weight_class: 700)
    end

    it "emits one FieldChange per differing field" do
      changes = described_class.new(left, right).diff.field_changes
      fields = changes.map(&:field).sort
      expect(fields).to eq(%w[family_name postscript_name weight_class])
    end
  end

  describe "#diff codepoint deltas" do
    let(:left) do
      report(
        codepoint_ranges: [
          Fontisan::Models::Audit::CodepointRange.new(first_cp: 0x41, last_cp: 0x4A),
        ],
      )
    end
    let(:right) do
      report(
        codepoint_ranges: [
          Fontisan::Models::Audit::CodepointRange.new(first_cp: 0x43, last_cp: 0x4C),
        ],
      )
    end

    it "counts added codepoints (in right, not left)" do
      diff = described_class.new(left, right).diff
      # right has 0x43-0x4C (10 cps), left has 0x41-0x4A (10 cps)
      # intersection: 0x43-0x4A (8 cps)
      # added: 0x4B-0x4C (2 cps)
      # removed: 0x41-0x42 (2 cps)
      expect(diff.codepoints.added_count).to eq(2)
      expect(diff.codepoints.removed_count).to eq(2)
      expect(diff.codepoints.unchanged_count).to eq(8)
    end

    it "coalesces added codepoints into ranges" do
      diff = described_class.new(left, right).diff
      expect(diff.codepoints.added.first.first_cp).to eq(0x4B)
      expect(diff.codepoints.added.first.last_cp).to eq(0x4C)
    end

    it "coalesces removed codepoints into ranges" do
      diff = described_class.new(left, right).diff
      expect(diff.codepoints.removed.first.first_cp).to eq(0x41)
      expect(diff.codepoints.removed.first.last_cp).to eq(0x42)
    end
  end

  describe "#diff structural inventories" do
    let(:left) do
      report(
        opentype_layout: Fontisan::Models::Audit::OpenTypeLayout.new(
          scripts: %w[latn grek],
          features: %w[liga kern],
          by_script: [], has_gsub: true, has_gpos: true
        ),
      )
    end
    let(:right) do
      report(
        opentype_layout: Fontisan::Models::Audit::OpenTypeLayout.new(
          scripts: %w[latn cyrl],
          features: %w[liga dlig kern],
          by_script: [], has_gsub: true, has_gpos: true
        ),
      )
    end

    it "diffs OpenType features as a set" do
      diff = described_class.new(left, right).diff
      expect(diff.added_features).to eq(["dlig"])
      expect(diff.removed_features).to eq([])
    end

    it "diffs OpenType scripts as a set" do
      diff = described_class.new(left, right).diff
      expect(diff.added_scripts).to eq(["cyrl"])
      expect(diff.removed_scripts).to eq(["grek"])
    end

    it "handles missing opentype_layout on one side (Type 1)" do
      diff = described_class.new(report, right).diff
      expect(diff.added_scripts).to include("cyrl", "latn")
      expect(diff.removed_scripts).to eq([])
    end
  end

  describe "#diff with UCD blocks and CLDR languages" do
    let(:left) do
      report(
        blocks: [
          Fontisan::Models::Audit::AuditBlock.new(name: "Basic Latin",
                                                  first_cp: 0, last_cp: 0x7F,
                                                  range: "U+0000-U+007F",
                                                  total: 128, covered: 100,
                                                  fill_ratio: 0.78,
                                                  complete: false),
        ],
        language_coverage: [
          Fontisan::Models::Cldr::LanguageCoverage.new(
            language: "en", covered: 26, total: 26,
            coverage_ratio: 1.0, fully_supported: true
          ),
        ],
      )
    end
    let(:right) do
      report(
        blocks: [
          Fontisan::Models::Audit::AuditBlock.new(name: "Basic Latin",
                                                  first_cp: 0, last_cp: 0x7F,
                                                  range: "U+0000-U+007F",
                                                  total: 128, covered: 100,
                                                  fill_ratio: 0.78,
                                                  complete: false),
          Fontisan::Models::Audit::AuditBlock.new(name: "Greek and Coptic",
                                                  first_cp: 0x370, last_cp: 0x3FF,
                                                  range: "U+0370-U+03FF",
                                                  total: 144, covered: 70,
                                                  fill_ratio: 0.48,
                                                  complete: false),
        ],
        language_coverage: [
          Fontisan::Models::Cldr::LanguageCoverage.new(
            language: "en", covered: 26, total: 26,
            coverage_ratio: 1.0, fully_supported: true
          ),
          Fontisan::Models::Cldr::LanguageCoverage.new(
            language: "fr", covered: 30, total: 30,
            coverage_ratio: 1.0, fully_supported: true
          ),
        ],
      )
    end

    it "diffs UCD block names" do
      diff = described_class.new(left, right).diff
      expect(diff.added_blocks).to eq(["Greek and Coptic"])
      expect(diff.removed_blocks).to eq([])
    end

    it "diffs CLDR language coverage" do
      diff = described_class.new(left, right).diff
      expect(diff.added_languages).to eq(["fr"])
      expect(diff.removed_languages).to eq([])
    end
  end

  describe "#diff source attribution" do
    let(:left)  { report(source_file: "/path/a.ttf") }
    let(:right) { report(source_file: "/path/b.ttf") }

    it "records left_source and right_source" do
      diff = described_class.new(left, right).diff
      expect(diff.left_source).to eq("/path/a.ttf")
      expect(diff.right_source).to eq("/path/b.ttf")
    end
  end

  describe "#diff nil handling" do
    it "serializes nil fields as empty strings" do
      left = report(postscript_name: nil)
      right = report(postscript_name: "Foo")
      change = described_class.new(left, right).diff.field_changes.first
      expect(change.left).to eq("")
      expect(change.right).to eq("Foo")
    end
  end
end
