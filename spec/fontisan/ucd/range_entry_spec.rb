# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/range_entry"

RSpec.describe Fontisan::Ucd::RangeEntry do
  let(:entry) { described_class.new(0x41, 0x5A, "Basic Latin") }

  describe "#covers?" do
    it "returns true for codepoints inside the range" do
      expect(entry.covers?(0x41)).to be true
      expect(entry.covers?(0x5A)).to be true
      expect(entry.covers?(0x4B)).to be true
    end

    it "returns false for codepoints outside the range" do
      expect(entry.covers?(0x40)).to be false
      expect(entry.covers?(0x5B)).to be false
      expect(entry.covers?(0x00)).to be false
    end
  end

  describe "#size" do
    it "returns inclusive range size" do
      expect(entry.size).to eq(26)
    end

    it "returns 1 for single-codepoint range" do
      single = described_class.new(0x20, 0x20, "Space")
      expect(single.size).to eq(1)
    end
  end

  describe "<=>" do
    it "sorts by first_cp then last_cp" do
      a = described_class.new(0x10, 0x20, "a")
      b = described_class.new(0x10, 0x30, "b")
      c = described_class.new(0x40, 0x50, "c")

      expect([c, a, b].sort).to eq([a, b, c])
    end
  end

  describe "#== and #eql?" do
    it "compares all three fields" do
      e1 = described_class.new(0x41, 0x5A, "Basic Latin")
      e2 = described_class.new(0x41, 0x5A, "Basic Latin")
      e3 = described_class.new(0x41, 0x5A, "Other")

      expect(e1).to eq(e2)
      expect(e1.eql?(e2)).to be true
      expect(e1).not_to eq(e3)
    end

    it "preserves equality for hash keys" do
      e1 = described_class.new(0x41, 0x5A, "Basic Latin")
      e2 = described_class.new(0x41, 0x5A, "Basic Latin")
      expect(e1.hash).to eq(e2.hash)
    end
  end

  describe "#to_h / .from_h round-trip" do
    it "round-trips through hash" do
      hash = entry.to_h
      restored = described_class.from_h(hash)

      expect(restored).to eq(entry)
    end

    it "from_h accepts string keys" do
      string_hash = { "first_cp" => 0x41, "last_cp" => 0x5A, "name" => "Latin" }
      restored = described_class.from_h(string_hash)

      expect(restored.first_cp).to eq(0x41)
      expect(restored.last_cp).to eq(0x5A)
      expect(restored.name).to eq("Latin")
    end
  end
end
