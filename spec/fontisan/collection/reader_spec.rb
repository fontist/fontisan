# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "fontisan/collection/reader"
require "tmpdir"

RSpec.describe Fontisan::Collection::Reader do
  let(:ufo) { Fontisan::Ufo }
  let(:ttc_path) do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)
    stitcher.include_notdef(from: :latin, into: :latin)
    stitcher.include_codepoints([0x41], from: :latin, into: :latin)
    stitcher.include_notdef(from: :cjk, into: :cjk)
    stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

    path = File.join(Dir.mktmpdir, "out.ttc")
    stitcher.write_collection(path, format: :ttf).path
  end

  def make_font_with(name, cp)
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = 500
    g.add_unicode(cp)
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: 100, y: 0,   type: "line"),
                                     ufo::Point.new(x: 100, y: 100, type: "line"),
                                   ]))
    font.glyphs[name] = g
    font
  end

  describe ".open" do
    it "returns a Reader for a valid TTC" do
      expect(described_class.open(ttc_path)).to be_a(described_class)
    end

    it "raises ArgumentError for a non-collection file" do
      # Pass the TTC's first face extracted as a single TTF — that's a TTF, not a TTC.
      single_ttf = File.join(Dir.mktmpdir, "single.ttf")
      Fontisan::FontWriter.write_to_file(
        { "head" => Fontisan::FontLoader.load(ttc_path).table("head").raw_data },
        single_ttf,
        sfnt_version: 0x00010000,
      )
      expect do
        described_class.open(single_ttf)
      end.to raise_error(ArgumentError, /not a TTC\/OTC\/dfont/)
    end
  end

  describe "#face_count" do
    it "matches the underlying collection's num_fonts" do
      reader = described_class.new(ttc_path)
      expect(reader.face_count).to eq(2)
    end
  end

  describe "#each_face" do
    it "yields one face per face_count" do
      reader = described_class.new(ttc_path)
      expect { |b| reader.each_face(&b) }.to yield_control.exactly(2).times
    end

    it "returns an Enumerator when no block is given" do
      reader = described_class.new(ttc_path)
      enum = reader.each_face
      expect(enum).to be_an(Enumerator)
      expect(enum.size).to eq(2)
    end
  end

  describe "#stats" do
    it "returns one Stats per face with correct glyph + codepoint counts" do
      reader = described_class.new(ttc_path)
      stats = reader.stats

      expect(stats.size).to eq(2)
      expect(stats).to all(be_a(Fontisan::Collection::Reader::Stats))
      stats.each_with_index do |s, i|
        face = Fontisan::FontLoader.load(ttc_path, font_index: i)
        expect(s.glyph_count).to eq(face.table("maxp").num_glyphs)
        expect(s.codepoint_count).to eq(face.table("cmap").unicode_mappings.size)
      end
    end

    it "is idempotent — calling twice yields equal values" do
      reader = described_class.new(ttc_path)
      first = reader.stats
      second = reader.stats
      expect(second).to eq(first)
    end
  end

  describe "#cmap_union" do
    it "returns a Set that unions all faces' cmaps" do
      reader = described_class.new(ttc_path)
      union = reader.cmap_union

      expect(union).to be_a(Set)
      expect(union).to include(0x41, 0x4E00)
      expect(union.size).to eq(2)
    end
  end
end
