# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::CodepointSetDiff do
  let(:added_range)   { Fontisan::Models::Audit::CodepointRange.new(first_cp: 0x4B, last_cp: 0x4C) }
  let(:removed_range) { Fontisan::Models::Audit::CodepointRange.new(first_cp: 0x41, last_cp: 0x42) }

  let(:diff) do
    described_class.new(
      added: [added_range],
      removed: [removed_range],
      added_count: 2,
      removed_count: 2,
      unchanged_count: 8,
    )
  end

  it "exposes the added range collection" do
    expect(diff.added.length).to eq(1)
    expect(diff.added.first).to be_a(Fontisan::Models::Audit::CodepointRange)
  end

  it "exposes the removed range collection" do
    expect(diff.removed.first.first_cp).to eq(0x41)
  end

  it "exposes the count fields" do
    expect(diff.added_count).to eq(2)
    expect(diff.removed_count).to eq(2)
    expect(diff.unchanged_count).to eq(8)
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(diff.to_yaml)
    expect(restored.added_count).to eq(2)
    expect(restored.removed_count).to eq(2)
    expect(restored.unchanged_count).to eq(8)
    expect(restored.added.first.first_cp).to eq(0x4B)
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(diff.to_json)
    expect(restored.removed.first.last_cp).to eq(0x42)
  end

  it "constructs cleanly without specifying collections" do
    # lutaml-model defaults unset collections to nil; both shapes are valid.
    empty = described_class.new(added_count: 0, removed_count: 0, unchanged_count: 0)
    expect(empty.added).to be_nil.or eq([])
    expect(empty.removed).to be_nil.or eq([])
  end
end
