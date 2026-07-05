# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Kern do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    f.kerning["A B"] = -50.0
    f.kerning["@G1 B"] = -25.0
    f
  end

  describe "#write" do
    it "returns a FeatureOutput with GPOS / kern / lookup_type 2" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GPOS")
      expect(out.feature_tag).to eq("kern")
      expect(out.lookup_type).to eq(2)
    end

    it "extracts every kerning pair from font.kerning" do
      out = described_class.new(font).write
      pairs = out.data[:pairs]
      expect(pairs.size).to eq(2)

      pair_keys = pairs.map { |p| [p[:left], p[:right], p[:value]] }
      expect(pair_keys).to contain_exactly(
        ["A", "B", -50.0],
        ["@G1", "B", -25.0],
      )
    end

    it "flags group references (keys starting with @) with group: true" do
      out = described_class.new(font).write
      group_pair = out.data[:pairs].find { |p| p[:left] == "@G1" }
      expect(group_pair[:group_left]).to be(true)
      expect(group_pair[:group_right]).to be(false)
    end

    it "returns nil when the font has no kerning" do
      empty_font = Fontisan::Ufo::Font.new
      expect(described_class.new(empty_font).write).to be_nil
    end

    it "returns nil when font.kerning is nil (not parsed)" do
      font_without_kerning = Fontisan::Ufo::Font.new
      allow(font_without_kerning).to receive(:kerning).and_return(nil)
      expect(described_class.new(font_without_kerning).write).to be_nil
    end
  end
end
