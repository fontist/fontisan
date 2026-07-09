# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Mark do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    f.glyphs["A"] = Fontisan::Ufo::Glyph.new(name: "A")
    f.glyphs["A"].add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 700,
                                                       name: "top"))
    f.glyphs["B"] = Fontisan::Ufo::Glyph.new(name: "B")
    f.glyphs["B"].add_anchor(Fontisan::Ufo::Anchor.new(x: 90, y: 700,
                                                       name: "top"))

    acutecomb = Fontisan::Ufo::Glyph.new(name: "acutecomb")
    acutecomb.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 600,
                                                   name: "_top"))
    f.glyphs["acutecomb"] = acutecomb
    f
  end

  describe "#write" do
    it "returns a FeatureOutput tagged GPOS / mark / lookup_type 4" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GPOS")
      expect(out.feature_tag).to eq("mark")
      expect(out.lookup_type).to eq(4)
    end

    it "pairs every mark with every base that has the matching anchor" do
      out = described_class.new(font).write
      attachments = out.data[:attachments]

      expect(attachments["top"][:marks]).to eq("acutecomb" => [100, 600])
      expect(attachments["top"][:bases]).to eq("A" => [100, 700],
                                               "B" => [
                                                 90, 700
                                               ])
    end

    it "returns nil when the font has no mark glyphs" do
      empty_font = Fontisan::Ufo::Font.new
      empty_font.glyphs["A"] = Fontisan::Ufo::Glyph.new(name: "A")
      expect(described_class.new(empty_font).write).to be_nil
    end

    it "returns nil when mark glyphs exist but no base matches their class" do
      f = Fontisan::Ufo::Font.new
      mark = Fontisan::Ufo::Glyph.new(name: "acutecomb")
      mark.add_anchor(Fontisan::Ufo::Anchor.new(x: 0, y: 0, name: "_top"))
      f.glyphs["acutecomb"] = mark

      expect(described_class.new(f).write).to be_nil
    end
  end
end
