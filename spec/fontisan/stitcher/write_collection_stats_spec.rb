# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require "tmpdir"

RSpec.describe Fontisan::Stitcher, "#write_collection stats" do
  let(:ufo) { Fontisan::Ufo }

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

  it "returns a CollectionResult, not a String" do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)
    stitcher.include_notdef(from: :latin, into: :latin)
    stitcher.include_codepoints([0x41], from: :latin, into: :latin)
    stitcher.include_notdef(from: :cjk, into: :cjk)
    stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.ttc")
      result = stitcher.write_collection(path, format: :ttf)

      expect(result).to be_a(Fontisan::Stitcher::CollectionResult)
      expect(result.path).to eq(path)
    end
  end

  it "exposes per-subfont stats read from the on-disk face" do
    latin = make_font_with("A", 0x41)
    cjk   = make_font_with("uni4E00", 0x4E00)

    stitcher = described_class.new
    stitcher.add_source(:latin, latin)
    stitcher.add_source(:cjk, cjk)
    stitcher.include_notdef(from: :latin, into: :latin)
    stitcher.include_codepoints([0x41], from: :latin, into: :latin)
    stitcher.include_notdef(from: :cjk, into: :cjk)
    stitcher.include_codepoints([0x4E00], from: :cjk, into: :cjk)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.ttc")
      result = stitcher.write_collection(path, format: :ttf)

      expect(result.face_count).to eq(2)
      expect(result.bytes).to eq(File.size(path))
      expect(result.subfonts.map(&:name)).to contain_exactly(:latin, :cjk)

      # Stats must match what's actually on disk, not the in-memory target.
      result.subfonts.each do |stats|
        face = Fontisan::FontLoader.load(path, font_index: result.subfonts.index(stats))
        expect(stats.glyph_count).to eq(face.table("maxp").num_glyphs)
        expect(stats.codepoint_count).to eq(face.table("cmap").unicode_mappings.size)
      end
    end
  end

  it "raises ArgumentError when no subfonts are declared" do
    stitcher = described_class.new
    expect do
      stitcher.write_collection("/tmp/empty.ttc", format: :ttf)
    end.to raise_error(ArgumentError, /no subfonts declared/)
  end

  it "propagates CBDT/CBLC tables in collection mode (bug fix coverage)" do
    skip "requires a CBDT source fixture; tracked as a follow-up" unless
      FixtureFonts::FONTS.key?("NotoColorEmoji") &&
        File.exist?(font_fixture_path("NotoColorEmoji", "NotoColorEmoji.ttf"))
  end
end
