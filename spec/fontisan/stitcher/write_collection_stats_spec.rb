# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"
require_relative "../../support/cbdt_fixture"
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
    # Builds an in-memory CBDT source via CbdtFixture (no external
    # fixture needed). Stitches it with an outline donor covering a
    # shared codepoint. The output TTC must contain the CBDT/CBLC
    # tables on every face.
    shared_cp = 0x1F600

    outline = ufo::Font.new
    outline.info.units_per_em = 1000
    outline.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
    g = ufo::Glyph.new(name: "outline-emoji")
    g.width = 500
    g.add_unicode(shared_cp)
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: 500, y: 0, type: "line"),
                                     ufo::Point.new(x: 500, y: 100, type: "line"),
                                   ]))
    outline.glyphs["outline-emoji"] = g

    cbdt_dir = Dir.mktmpdir
    cbdt_path = File.join(cbdt_dir, "cbdt.ttf")
    Fontisan::SpecHelpers::CbdtFixture.write_font(
      codepoints: [shared_cp], path: cbdt_path,
    )
    cbdt_font = Fontisan::FontLoader.load(cbdt_path)

    stitcher = described_class.new
    stitcher.add_source(:outline, outline)
    stitcher.add_source(:cbdt, cbdt_font)
    stitcher.include_notdef(from: :outline, into: :main)
    stitcher.include_codepoints([shared_cp], from: :outline, into: :main)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.ttc")
      stitcher.write_collection(path, format: :ttf)

      File.open(path, "rb") do |io|
        ttc = Fontisan::TrueTypeCollection.read(io)
        face = ttc.font(0, io)
        expect(face.table_data).to include("CBDT"),
                                   "CBDT table missing from collection face (propagation regression)"
        expect(face.table_data).to include("CBLC"),
                                   "CBLC table missing from collection face (propagation regression)"

        # Stronger: also verify the shared codepoint resolves to the
        # outline glyph (advance_width 500), not the CBDT placeholder
        # (advance_width 1000). This catches the regression the PR's
        # outline_priority sibling test covers, in collection mode.
        cmap = face.table("cmap").unicode_mappings
        expect(cmap).to include(shared_cp)

        hmtx = face.table("hmtx")
        hhea = face.table("hhea")
        maxp_t = face.table("maxp")
        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)
        gid = cmap[shared_cp]
        metric = hmtx.metric_for(gid)
        expect(metric[:advance_width]).to eq(500),
                                          "shared codepoint mapped to CBDT placeholder (width 1000) " \
                                          "instead of outline glyph (width 500) in collection mode"
      end
    end
  end
end
