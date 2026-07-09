# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "tmpdir"

RSpec.describe "Collection pipeline" do
  let(:ufo) { Fontisan::Ufo }

  def make_font(name, codepoint, points = [[0, 0, "line"], [100, 0, "line"]])
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(codepoint)
    g.add_contour(ufo::Contour.new(points.map do |x, y, t|
      ufo::Point.new(x: x, y: y, type: t)
    end))
    font.glyphs[name] = g
    font
  end

  describe "TTC with multiple TTF subfonts" do
    it "writes and reopens a collection with correct font count" do
      latin = make_font("A", 0x41)
      greek = make_font("Alpha", 0x391)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, latin)
      stitcher.add_source(:greek, greek)
      stitcher.include_notdef(from: :latin, into: :latin)
      stitcher.include_codepoints([0x41], from: :latin, into: :latin)
      stitcher.include_notdef(from: :greek, into: :greek)
      stitcher.include_codepoints([0x391], from: :greek, into: :greek)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.ttc")
        stitcher.write_collection(path, format: :ttf)

        expect(File.binread(path, 4)).to eq("ttcf")
        collection = Fontisan::FontLoader.load_collection(path)
        expect(collection.num_fonts).to eq(2)

        all_cps = []
        collection.num_fonts.times do |i|
          font = Fontisan::FontLoader.load(path, font_index: i)
          all_cps.concat(font.table("cmap").unicode_mappings.keys)
        end
        expect(all_cps).to include(0x41, 0x391)
      end
    end
  end

  describe "CFF2 subfont compilation" do
    it "compiles a single CFF2 subfont to a valid OTF" do
      donor = make_font("A", 0x41)
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :latin)
      stitcher.include_codepoints([0x41], from: :d, into: :latin)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.otf")
        stitcher.write_to(path, format: :otf2, subfont: :latin)

        loaded = Fontisan::FontLoader.load(path)
        expect(loaded.has_table?("CFF2")).to be(true)
        expect(loaded.has_table?("CFF ")).to be(false)
      end
    end
  end
end
