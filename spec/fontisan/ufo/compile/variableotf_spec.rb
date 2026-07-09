# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::VariableOtf do
  let(:default_font) do
    f = Fontisan::Ufo::Font.new
    f.info.family_name = "Test"
    f.info.units_per_em = 1000
    f.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
    g = Fontisan::Ufo::Glyph.new(name: "A")
    g.width = 500
    g.add_unicode(0x41)
    g.add_contour(Fontisan::Ufo::Contour.new([
                                               Fontisan::Ufo::Point.new(x: 0,
                                                                        y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100,
                                                                        y: 0, type: "line"),
                                             ]))
    f.glyphs["A"] = g
    f
  end

  describe "#build_tables" do
    it "produces a variable OTF with fvar and STAT" do
      axes = [{ tag: "wght", min: 100, default: 400, max: 900, name_id: 256 }]
      orch = described_class.new(default_font, axes: axes)
      tables = orch.build_tables
      expect(tables).to have_key("fvar")
      expect(tables).to have_key("STAT")
      expect(tables).to have_key("CFF2")
    end
  end
end
