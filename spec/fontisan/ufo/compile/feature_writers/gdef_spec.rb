# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/feature_writers"

RSpec.describe Fontisan::Ufo::Compile::FeatureWriters::Gdef do
  let(:font) do
    f = Fontisan::Ufo::Font.new
    f.glyphs["A"] = Fontisan::Ufo::Glyph.new(name: "A")
    f.glyphs["A"].lib = Fontisan::Ufo::Lib.new("public.openTypeCategory" => "base")

    lig = Fontisan::Ufo::Glyph.new(name: "ffi.liga")
    lig.lib = Fontisan::Ufo::Lib.new("public.openTypeCategory" => "ligature")
    f.glyphs["ffi.liga"] = lig

    mark = Fontisan::Ufo::Glyph.new(name: "acutecomb")
    mark.add_anchor(Fontisan::Ufo::Anchor.new(x: 0, y: 0, name: "_top"))
    f.glyphs["acutecomb"] = mark

    f
  end

  describe "#write" do
    it "returns a FeatureOutput tagged GDEF with no feature_tag" do
      out = described_class.new(font).write
      expect(out.table_tag).to eq("GDEF")
      expect(out.feature_tag).to be_nil
    end

    it "classifies glyphs via public.openTypeCategory lib entry" do
      out = described_class.new(font).write
      expect(out.data[:classes]["A"]).to eq(1)        # base
      expect(out.data[:classes]["ffi.liga"]).to eq(2) # ligature
    end

    it "falls back to anchor-name heuristic for unclassified glyphs" do
      out = described_class.new(font).write
      expect(out.data[:classes]["acutecomb"]).to eq(3)
    end

    it "returns nil when no glyphs classify" do
      empty_font = Fontisan::Ufo::Font.new
      empty_font.glyphs["plain"] = Fontisan::Ufo::Glyph.new(name: "plain")
      expect(described_class.new(empty_font).write).to be_nil
    end
  end
end
