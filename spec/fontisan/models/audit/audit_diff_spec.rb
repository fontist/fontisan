# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::AuditDiff do
  let(:field_change) do
    Fontisan::Models::Audit::FieldChange.new(
      field: "weight_class", left: "400", right: "700",
    )
  end
  let(:codepoint_diff) do
    Fontisan::Models::Audit::CodepointSetDiff.new(
      added_count: 5, removed_count: 3, unchanged_count: 100,
    )
  end

  let(:diff) do
    described_class.new(
      left_source: "/path/a.ttf",
      right_source: "/path/b.ttf",
      field_changes: [field_change],
      codepoints: codepoint_diff,
      added_features: %w[dlig],
      removed_features: [],
      added_scripts: %w[cyrl],
      removed_scripts: %w[grek],
      added_blocks: ["Greek and Coptic"],
      removed_blocks: [],
      added_languages: ["fr"],
      removed_languages: [],
    )
  end

  it "exposes source paths" do
    expect(diff.left_source).to eq("/path/a.ttf")
    expect(diff.right_source).to eq("/path/b.ttf")
  end

  it "exposes field_changes collection" do
    expect(diff.field_changes.length).to eq(1)
    expect(diff.field_changes.first).to be_a(Fontisan::Models::Audit::FieldChange)
  end

  it "exposes codepoints CodepointSetDiff" do
    expect(diff.codepoints).to be_a(Fontisan::Models::Audit::CodepointSetDiff)
    expect(diff.codepoints.added_count).to eq(5)
  end

  it "exposes the structural add/remove lists" do
    expect(diff.added_features).to eq(%w[dlig])
    expect(diff.removed_scripts).to eq(%w[grek])
    expect(diff.added_blocks).to eq(["Greek and Coptic"])
    expect(diff.added_languages).to eq(["fr"])
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(diff.to_yaml)
    expect(restored.left_source).to eq("/path/a.ttf")
    expect(restored.field_changes.first.field).to eq("weight_class")
    expect(restored.codepoints.added_count).to eq(5)
    expect(restored.added_features).to eq(%w[dlig])
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(diff.to_json)
    expect(restored.right_source).to eq("/path/b.ttf")
    expect(restored.added_scripts).to eq(%w[cyrl])
  end

  describe "#empty?" do
    it "returns true when nothing differs" do
      empty_diff = described_class.new(
        field_changes: [],
        codepoints: Fontisan::Models::Audit::CodepointSetDiff.new(
          added_count: 0, removed_count: 0, unchanged_count: 0,
        ),
      )
      expect(empty_diff).to be_empty
    end

    it "returns false when there are field changes" do
      expect(diff).not_to be_empty
    end
  end

  describe "added_codepoints / removed_codepoints convenience methods" do
    it "delegates to codepoints counts" do
      expect(diff.added_codepoints).to eq(5)
      expect(diff.removed_codepoints).to eq(3)
    end

    it "returns 0 when codepoints is nil" do
      bare = described_class.new
      expect(bare.added_codepoints).to eq(0)
      expect(bare.removed_codepoints).to eq(0)
    end
  end
end
