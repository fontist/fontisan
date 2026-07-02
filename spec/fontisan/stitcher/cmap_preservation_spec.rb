# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "fontisan/stitcher"

# Regression tests for BUG-stitcher-drops-plane1-codepoints.md
#
# The bug claimed that Plane 1 codepoints (U+10000..U+1FFFF) and the
# topmost consecutive gid range of certain donors were silently
# dropped by the Stitcher. These specs verify the current
# implementation preserves all cmap entries.
RSpec.describe "Stitcher cmap preservation (regression)", :donors do
  # Skip if required donor files aren't present
  before do
    skip "donor files not available" unless File.exist?(
      "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Lentariso-Regular.ttf",
    )
  end

  let(:lentariso_path) { "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Lentariso-Regular.ttf" }

  it "preserves all Plane 1 codepoints from Lentariso" do
    src = Fontisan::FontLoader.load(lentariso_path)
    src_cmap = src.table("cmap").unicode_mappings
    plane1 = src_cmap.keys.select { |cp| cp >= 0x10000 && cp <= 0x1FFFF }

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:lentariso, src)
    stitcher.include_notdef(from: :lentariso, into: :main)
    stitcher.include_codepoints(plane1, from: :lentariso, into: :main)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf, subfont: :main)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      out_plane1 = out_cmap.keys.select { |cp| cp >= 0x10000 && cp <= 0x1FFFF }

      expect(out_plane1.size).to eq(plane1.size),
                                 "expected #{plane1.size} Plane 1 codepoints, got #{out_plane1.size}"
    end
  end

  it "preserves the topmost consecutive gid range of Kedebideri" do
    kedebideri_path = "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/Kedebideri-Regular.ttf"
    skip "Kedebideri not present" unless File.exist?(kedebideri_path)

    src = Fontisan::FontLoader.load(kedebideri_path)
    src_cmap = src.table("cmap").unicode_mappings
    beria_erfe = src_cmap.keys.select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:kedebideri, src)
    stitcher.include_notdef(from: :kedebideri, into: :main)
    stitcher.include_codepoints(beria_erfe, from: :kedebideri, into: :main)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf, subfont: :main)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      out_beria = out_cmap.keys.select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }

      expect(out_beria.size).to eq(beria_erfe.size),
                                "expected #{beria_erfe.size} Beria Erfe cps, got #{out_beria.size}; " \
                                "dropped: #{(beria_erfe - out_beria).map { |cp| format('U+%04X', cp) }.join(', ')}"
    end
  end

  # Regression for 0.4.1 regression: O(1) extraction returned nil for
  # CFF sources, dropping ALL glyphs from OTF donors.
  it "preserves Tangut codepoints from an OTF/CFF source" do
    tangut_path = "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/NotoSerifTangut-Regular.otf"
    skip "NotoSerifTangut not present" unless File.exist?(tangut_path)

    src = Fontisan::FontLoader.load(tangut_path)
    src_cmap = src.table("cmap").unicode_mappings
    tangut = src_cmap.keys.select { |cp| cp >= 0x17000 && cp <= 0x187FF }.first(100)

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:tangut, src)
    stitcher.include_notdef(from: :tangut, into: :main)
    stitcher.include_codepoints(tangut, from: :tangut, into: :main)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf, subfont: :main)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      out_tangut = out_cmap.keys.select { |cp| cp >= 0x17000 && cp <= 0x187FF }

      expect(out_tangut.size).to eq(tangut.size),
                                 "expected #{tangut.size} Tangut cps from OTF source, got #{out_tangut.size}"
    end
  end

  # Regression for BUG-stitcher-drops-isolated-cps.md: the O(1)
  # extraction path returned nil for compound (composite) TrueType
  # glyphs, silently dropping them. NotoSansCuneiform's U+12399
  # (gid 925) is a compound glyph composed of two references to
  # gid 783 at different x-offsets. Many Noto donors use compound
  # glyphs heavily (TaiTham: 594, DivesAkuru: 414, TaiYo: 1007).
  it "flattens and preserves compound glyphs from a TTF source" do
    cuneiform_path = "/Users/mulgogi/src/essenfont/essenfont/references/input-fonts/NotoSansCuneiform-Regular.ttf"
    skip "NotoSansCuneiform not present" unless File.exist?(cuneiform_path)

    src = Fontisan::FontLoader.load(cuneiform_path)

    stitcher = Fontisan::Stitcher.new
    stitcher.add_source(:cuneiform, src)
    stitcher.include_notdef(from: :cuneiform, into: :main)
    stitcher.include_codepoints([0x12399], from: :cuneiform, into: :main)

    Dir.mktmpdir do |dir|
      out_path = File.join(dir, "out.ttf")
      stitcher.write_to(out_path, format: :ttf, subfont: :main)

      out = Fontisan::FontLoader.load(out_path)
      out_cmap = out.table("cmap").unicode_mappings
      expect(out_cmap.key?(0x12399)).to be(true),
                                        "U+12399 (compound glyph) was silently dropped"

      out_glyf = out.table("glyf")
      out_loca = out.table("loca")
      out_head = out.table("head")
      out_maxp = out.table("maxp")
      if out_loca.respond_to?(:parse_with_context)
        out_loca.parse_with_context(out_head.index_to_loc_format, out_maxp.num_glyphs)
      end
      glyph = out_glyf.glyph_for(1, out_loca, out_head)
      expect(glyph).not_to be_nil
      is_simple = glyph.respond_to?(:simple?) && glyph.simple?
      expect(is_simple).to be(true), "flattened compound should be a simple glyph in the output"
      contour_count = glyph.end_pts_of_contours&.size || 0
      expect(contour_count).to be > 0, "flattened compound has no contours"
    end
  end
end
