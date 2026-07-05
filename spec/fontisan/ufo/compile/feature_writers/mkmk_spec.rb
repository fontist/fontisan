# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Mkmk do
  let(:font) do
    f = Fontisan::Ufo::Font.new

    # acutecomb: a mark with _top (mark anchor) + _topmkmk (attach FROM)
    acutecomb = Fontisan::Ufo::Glyph.new(name: "acutecomb")
    acutecomb.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 600, name: "_top"))
    acutecomb.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 650, name: "_topmkmk"))
    f.glyphs["acutecomb"] = acutecomb

    # dieresiscomb: a mark with topmkmk (attach TO) + _top (mark anchor)
    dieresiscomb = Fontisan::Ufo::Glyph.new(name: "dieresiscomb")
    dieresiscomb.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 700, name: "topmkmk"))
    dieresiscomb.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 750, name: "_top"))
    f.glyphs["dieresiscomb"] = dieresiscomb
    f
  end

  describe "#write" do
    it "returns a FeatureOutput tagged GPOS / mkmk / lookup_type 6" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GPOS")
      expect(out.feature_tag).to eq("mkmk")
      expect(out.lookup_type).to eq(6)
    end

    it "pairs marks with _<name>mkmk against base marks with <name>mkmk" do
      out = described_class.new(font).write
      attachments = out.data[:attachments]

      expect(attachments["top"][:marks]).to eq("acutecomb" => [100, 650])
      expect(attachments["top"][:base_marks]).to eq("dieresiscomb" => [100, 700])
    end

    it "returns nil when no glyph has _<name>mkmk anchors" do
      empty_font = Fontisan::Ufo::Font.new
      mark = Fontisan::Ufo::Glyph.new(name: "acutecomb")
      mark.add_anchor(Fontisan::Ufo::Anchor.new(x: 0, y: 0, name: "_top"))
      empty_font.glyphs["acutecomb"] = mark
      expect(described_class.new(empty_font).write).to be_nil
    end

    it "returns nil when marks have _<name>mkmk but no matching <name>mkmk base marks" do
      f = Fontisan::Ufo::Font.new
      m = Fontisan::Ufo::Glyph.new(name: "acutecomb")
      m.add_anchor(Fontisan::Ufo::Anchor.new(x: 0, y: 0, name: "_topmkmk"))
      f.glyphs["acutecomb"] = m
      expect(described_class.new(f).write).to be_nil
    end
  end
end
