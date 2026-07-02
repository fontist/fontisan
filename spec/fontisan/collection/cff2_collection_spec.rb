# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "tmpdir"

# Verifies that CFF2 subfonts compile and load correctly.
# TODO 04, 05: full collection assembly with multiple CFF2 subfonts
# is pending Collection::Builder improvements.
RSpec.describe "CFF2 subfont compilation" do
  let(:ufo) { Fontisan::Ufo }

  def make_font(name, codepoint, points = [[0, 0, "line"], [100, 0, "line"]])
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(codepoint)
    g.add_contour(ufo::Contour.new(points.map { |x, y, t| ufo::Point.new(x: x, y: y, type: t) }))
    font.glyphs[name] = g
    font
  end

  describe "Otf2Compiler + Stitcher" do
    it "compiles a single CFF2 subfont to a valid OTF" do
      donor = make_font("A", 0x41)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :latin)
      stitcher.include_codepoints([0x41], from: :d, into: :latin)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.otf")
        stitcher.write_to(path, format: :otf2, subfont: :latin)

        expect(File.binread(path, 4)).to eq("OTTO")
        loaded = Fontisan::FontLoader.load(path)
        expect(loaded.has_table?("CFF2")).to be(true)
        expect(loaded.has_table?("CFF ")).to be(false)
        expect(loaded.table("cmap").unicode_mappings.key?(0x41)).to be(true)
      end
    end
  end

  describe "TTC header format" do
    it "writes the 'ttcf' signature" do
      donor = make_font("A", 0x41)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41], from: :d, into: :main)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "ttc.ttc")
        stitcher.write_collection(path, format: :ttf)
        expect(File.binread(path, 4)).to eq("ttcf")
      end
    end
  end
end
