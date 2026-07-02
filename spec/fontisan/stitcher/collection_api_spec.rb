# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "tmpdir"

RSpec.describe "Stitcher explicit subfont declaration" do
  let(:ufo) { Fontisan::Ufo }

  def make_font_with(name, cp, points = [[0, 0, "line"], [100, 0, "line"], [100, 100, "line"]])
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(cp)
    g.add_contour(ufo::Contour.new(points.map do |x, y, t|
      ufo::Point.new(x: x, y: y, type: t)
    end))
    font.glyphs[name] = g
    font
  end

  describe "subfont assignment" do
    it "routes bindings to named subfonts via into:" do
      donor = make_font_with("A", 0x41)
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41], from: :d, into: :main)

      expect(stitcher.subfonts.key?(:main)).to be(true)
      expect(stitcher.subfonts[:main].size).to eq(2) # notdef + A
      expect(stitcher.subfont_names).to eq([:main])
    end

    it "supports multiple named subfonts" do
      latin = make_font_with("A", 0x41)
      cjk = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, latin)
      stitcher.add_source(:cjk, cjk)
      stitcher.include_notdef(from: :latin, into: :latin)
      stitcher.include_codepoints([0x41], from: :latin, into: :latin)
      stitcher.include_notdef(from: :cjk, into: :cjk)
      stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

      expect(stitcher.subfont_names.sort).to eq(%i[cjk latin])
      expect(stitcher.subfonts[:latin].size).to eq(2)
      expect(stitcher.subfonts[:cjk].size).to eq(2)
    end
  end

  describe "single font output" do
    it "writes one named subfont as a TTF" do
      donor = make_font_with("A", 0x41)
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:d, donor)
      stitcher.include_notdef(from: :d, into: :main)
      stitcher.include_codepoints([0x41], from: :d, into: :main)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.ttf")
        stitcher.write_to(path, format: :ttf, subfont: :main)
        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.table("cmap").unicode_mappings.key?(0x41)).to be(true)
      end
    end

    it "writes a specific named subfont from a multi-subfont stitcher" do
      latin = make_font_with("A", 0x41)
      cjk = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, latin)
      stitcher.add_source(:cjk, cjk)
      stitcher.include_notdef(from: :latin, into: :latin)
      stitcher.include_codepoints([0x41], from: :latin, into: :latin)
      stitcher.include_notdef(from: :cjk, into: :cjk)
      stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "cjk.ttf")
        stitcher.write_to(path, format: :ttf, subfont: :cjk)
        reopened = Fontisan::FontLoader.load(path)
        expect(reopened.table("cmap").unicode_mappings.key?(0x4E00)).to be(true)
        expect(reopened.table("cmap").unicode_mappings.key?(0x41)).to be(false)
      end
    end
  end

  describe "collection output" do
    it "writes a TTC with all declared subfonts" do
      latin = make_font_with("A", 0x41)
      cjk = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, latin)
      stitcher.add_source(:cjk, cjk)
      stitcher.include_notdef(from: :latin, into: :latin)
      stitcher.include_codepoints([0x41], from: :latin, into: :latin)
      stitcher.include_notdef(from: :cjk, into: :cjk)
      stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.ttc")
        stitcher.write_collection(path, format: :ttf)

        expect(File.exist?(path)).to be(true)
        expect(File.binread(path, 4)).to eq("ttcf")

        collection = Fontisan::FontLoader.load_collection(path)
        expect(collection.num_fonts).to eq(2)

        all_cps = []
        collection.num_fonts.times do |i|
          font = Fontisan::FontLoader.load(path, font_index: i)
          all_cps.concat(font.table("cmap").unicode_mappings.keys)
        end
        expect(all_cps).to include(0x41, 0x4E00)
      end
    end

    it "writes an OTC with CFF2 subfonts" do
      latin = make_font_with("A", 0x41)
      cjk = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, latin)
      stitcher.add_source(:cjk, cjk)
      stitcher.include_notdef(from: :latin, into: :latin)
      stitcher.include_codepoints([0x41], from: :latin, into: :latin)
      stitcher.include_notdef(from: :cjk, into: :cjk)
      stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.otc")
        stitcher.write_collection(path, format: :otf2)

        expect(File.exist?(path)).to be(true)
        expect(File.binread(path, 4)).to eq("ttcf")

        collection = Fontisan::FontLoader.load_collection(path)
        collection.num_fonts.times do |i|
          font = Fontisan::FontLoader.load(path, font_index: i)
          expect(font.has_table?("CFF2")).to be(true)
        end
      end
    end

    it "raises when no subfonts are declared" do
      stitcher = Fontisan::Stitcher.new
      expect { stitcher.write_collection("/tmp/empty.ttc", format: :ttf) }
        .to raise_error(ArgumentError, /no subfonts declared/)
    end
  end
end
