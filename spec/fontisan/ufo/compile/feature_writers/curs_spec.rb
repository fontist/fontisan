# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Curs do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    g1 = Fontisan::Ufo::Glyph.new(name: "alef")
    g1.add_anchor(Fontisan::Ufo::Anchor.new(x: 0, y: 100, name: "entry"))
    g1.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 100, name: "exit"))
    f.glyphs["alef"] = g1

    g2 = Fontisan::Ufo::Glyph.new(name: "beh")
    g2.add_anchor(Fontisan::Ufo::Anchor.new(x: 50, y: 50, name: "entry"))
    f.glyphs["beh"] = g2
    f
  end

  describe "#write" do
    it "returns a FeatureOutput tagged GPOS / curs / lookup_type 3" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GPOS")
      expect(out.feature_tag).to eq("curs")
      expect(out.lookup_type).to eq(3)
    end

    it "emits an attachment entry per glyph with entry and/or exit anchors" do
      out = described_class.new(font).write
      expect(out.data[:attachments].keys).to contain_exactly("alef", "beh")
    end

    it "captures both entry and exit anchor positions when present" do
      out = described_class.new(font).write
      alef = out.data[:attachments]["alef"]
      expect(alef[:entry]).to eq([0, 100])
      expect(alef[:exit]).to eq([100, 100])
    end

    it "captures only entry when no exit anchor is present" do
      out = described_class.new(font).write
      beh = out.data[:attachments]["beh"]
      expect(beh[:entry]).to eq([50, 50])
      expect(beh[:exit]).to be_nil
    end

    it "returns nil when no glyph has entry or exit anchors" do
      empty_font = Fontisan::Ufo::Font.new
      empty_font.glyphs["A"] = Fontisan::Ufo::Glyph.new(name: "A")
      expect(described_class.new(empty_font).write).to be_nil
    end
  end
end
