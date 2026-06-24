# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/index"
require "fontisan/ucd/range_entry"
require "tmpdir"

RSpec.describe Fontisan::Ucd::Index do
  let(:entries) do
    [
      Fontisan::Ucd::RangeEntry.new(0x0000, 0x007F, "Basic Latin"),
      Fontisan::Ucd::RangeEntry.new(0x0080, 0x00FF, "Latin-1 Supplement"),
      Fontisan::Ucd::RangeEntry.new(0x4E00, 0x9FFF, "CJK Unified Ideographs"),
    ]
  end

  let(:index) { described_class.new(entries) }

  describe "#lookup" do
    it "finds the range name for a codepoint" do
      expect(index.lookup(0x0041)).to eq("Basic Latin")
      expect(index.lookup(0x00A0)).to eq("Latin-1 Supplement")
      expect(index.lookup(0x4E2D)).to eq("CJK Unified Ideographs")
    end

    it "returns nil for codepoints not in any range" do
      expect(index.lookup(0x10000)).to be_nil
    end

    it "handles boundary codepoints" do
      expect(index.lookup(0x007F)).to eq("Basic Latin")
      expect(index.lookup(0x0080)).to eq("Latin-1 Supplement")
    end
  end

  describe "#each_overlapping" do
    it "yields every overlapping entry" do
      results = index.each_overlapping(0x0040, 0x00FF).to_a
      names = results.map(&:name)

      expect(names).to eq(["Basic Latin", "Latin-1 Supplement"])
    end

    it "yields a single entry for narrow query" do
      results = index.each_overlapping(0x4E00, 0x4E10).to_a
      expect(results.map(&:name)).to eq(["CJK Unified Ideographs"])
    end

    it "returns empty for a range with no overlap" do
      results = index.each_overlapping(0xA000, 0xA100).to_a
      expect(results).to be_empty
    end

    it "returns an enumerator when no block given" do
      enum = index.each_overlapping(0x0040, 0x00FF)
      expect(enum).to be_an(Enumerator)
      expect(enum.count).to eq(2)
    end
  end

  describe "#size and #each" do
    it "reports entry count" do
      expect(index.size).to eq(3)
    end

    it "is enumerable" do
      expect(index.map(&:name)).to include("Basic Latin")
    end
  end

  describe "#save / .load round-trip" do
    it "round-trips through YAML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "blocks.yml")
        index.save(path)
        loaded = described_class.load(path)

        expect(loaded.size).to eq(index.size)
        expect(loaded.lookup(0x0041)).to eq("Basic Latin")
        expect(loaded.lookup(0x4E2D)).to eq("CJK Unified Ideographs")
      end
    end
  end

  describe ".from_triples" do
    it "builds an Index from raw triples" do
      triples = [
        [0x0000, 0x007F, "Basic Latin"],
        [0x0080, 0x00FF, "Latin-1 Supplement"],
      ]
      index = described_class.from_triples(triples)

      expect(index.size).to eq(2)
      expect(index.lookup(0x0041)).to eq("Basic Latin")
    end
  end
end
