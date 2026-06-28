# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_builder"

RSpec.describe Fontisan::FontBuilder::FontModel do
  describe "#initialize" do
    it "starts with an empty cmap" do
      expect(described_class.new.cmap).to eq({})
    end

    it "starts with a single .notdef glyph at gid 0" do
      model = described_class.new
      expect(model.glyphs.keys).to eq([0])
      expect(model.glyphs[0]).to be_a(Fontisan::FontBuilder::GlyphEntry)
    end

    it "defaults to unitsPerEm 1000" do
      expect(described_class.new.units_per_em).to eq(1000)
    end
  end

  describe "#num_glyphs" do
    it "is 1 when only .notdef exists" do
      expect(described_class.new.num_glyphs).to eq(1)
    end

    it "grows when glyphs are added" do
      model = described_class.new
      model.glyphs[5] = Fontisan::FontBuilder::GlyphEntry.new
      expect(model.num_glyphs).to eq(6)
    end
  end

  describe "#allocate_gid" do
    it "returns the next free gid" do
      expect(described_class.new.allocate_gid).to eq(1)
    end

    it "creates an empty GlyphEntry at the new gid" do
      model = described_class.new
      gid = model.allocate_gid
      expect(model.glyphs[gid]).to be_a(Fontisan::FontBuilder::GlyphEntry)
    end
  end

  describe "#assign_codepoint" do
    it "allocates a new gid for a previously-unseen codepoint" do
      model = described_class.new
      gid = model.assign_codepoint(0x41)
      expect(gid).to eq(1)
      expect(model.cmap[0x41]).to eq(1)
    end

    it "returns the existing gid for a codepoint already in the cmap" do
      model = described_class.new
      first = model.assign_codepoint(0x41)
      second = model.assign_codepoint(0x41)
      expect(second).to eq(first)
    end
  end

  describe "#sorted_codepoints" do
    it "returns codepoints in ascending order" do
      model = described_class.new
      model.cmap = { 0x1F600 => 5, 0x41 => 1, 0x9759 => 3 }
      expect(model.sorted_codepoints).to eq([0x41, 0x9759, 0x1F600])
    end
  end
end
