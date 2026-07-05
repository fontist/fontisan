# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Kern2 do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    f.kerning["A B"] = -50.0
    f.kerning["@G1 B"] = -25.0
    f
  end

  describe "#write" do
    it "returns a FeatureOutput tagged GPOS / kern / lookup_type 2 with format 2" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GPOS")
      expect(out.feature_tag).to eq("kern")
      expect(out.lookup_type).to eq(2)
      expect(out.data[:format]).to eq(2)
    end

    it "extracts kerning pairs like the basic Kern writer" do
      out = described_class.new(font).write
      pairs = out.data[:pairs]
      expect(pairs.size).to eq(2)
      expect(pairs.map { |p| [p[:left], p[:right]] }).to contain_exactly(
        ["A", "B"], ["@G1", "B"]
      )
    end

    it "flags group references" do
      out = described_class.new(font).write
      group_pair = out.data[:pairs].find { |p| p[:left] == "@G1" }
      expect(group_pair[:group_left]).to be(true)
    end

    it "returns nil when font has no kerning" do
      empty_font = Fontisan::Ufo::Font.new
      expect(described_class.new(empty_font).write).to be_nil
    end
  end
end
