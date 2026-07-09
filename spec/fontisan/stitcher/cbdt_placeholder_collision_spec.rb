# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/fontisan/stitcher"
require_relative "../../support/cbdt_fixture"
require "tmpdir"

# Regression coverage for the CBDT-placeholder-overwrites-outline bug.
#
# Before the Layer#add contract was tightened (raise-on-conflict +
# UniqueGlyphName helper), CbdtPropagator#add_placeholder_glyphs named
# its placeholders "gid{N}" — the SAME scheme Source#extract_truetype_glyph
# uses for outline glyphs from TTF donors, AND the same scheme a caller
# might use directly when constructing a UFO outline donor. When both
# donors contributed a glyph with the same name, Layer#add silently
# hash-overwrote the earlier one. The overwritten glyph's codepoints
# dropped out of the cmap; CJK Ext G in Essenfont-Regular.ttc lost
# 3,917 of 4,939 codepoints this way.
#
# This spec reproduces the failure mode minimally. The outline donor
# (UFO) carries a glyph NAMED "gid1" — matching the CBDT source's
# placeholder at GID 1. The two donors cover DISJOINT codepoints so
# the cmap-priority fix (PR #107 / outline-first ordering) does NOT
# apply; the only path that keeps both glyphs in the target is
# Layer#add raising on conflict + UniqueGlyphName allocating "gid1.1"
# for the placeholder.
#
# Without the fix, the CBDT placeholder overwrites the outline glyph
# and cp_a disappears from the cmap entirely.
RSpec.describe Fontisan::Stitcher do
  context "CBDT placeholder vs outline glyph naming" do
    let(:ufo) { Fontisan::Ufo }

    # Build a UFO outline donor with one glyph named "gid1" (matching
    # the CBDT source's placeholder naming scheme) at cp_a with advance
    # 500.
    def make_outline_donor_with_gid1_name(cp_a)
      font = ufo::Font.new
      font.info.units_per_em = 1000
      font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

      g = ufo::Glyph.new(name: "gid1") # collides with CBDT placeholder name
      g.width = 500
      g.add_unicode(cp_a)
      g.add_contour(ufo::Contour.new([
                                       ufo::Point.new(x: 0, y: 0, type: "line"),
                                       ufo::Point.new(x: 500, y: 0,
                                                      type: "line"),
                                       ufo::Point.new(x: 500, y: 100,
                                                      type: "line"),
                                     ]))
      font.glyphs["gid1"] = g
      font
    end

    it "outline glyph and CBDT placeholder both survive when they share a name" do
      cp_a = 0x41    # 'A' — only in outline donor
      cp_b = 0x1F600 # emoji — only in CBDT donor

      outline = make_outline_donor_with_gid1_name(cp_a)

      cbdt_dir = Dir.mktmpdir
      cbdt_path = File.join(cbdt_dir, "cbdt.ttf")
      Fontisan::SpecHelpers::CbdtFixture.write_font(codepoints: [cp_b],
                                                    path: cbdt_path)
      cbdt_font = Fontisan::FontLoader.load(cbdt_path)

      stitcher = described_class.new
      stitcher.add_source(:outline, outline)
      stitcher.add_source(:cbdt, cbdt_font)
      stitcher.include_notdef(from: :outline, into: :main)
      stitcher.include_codepoints([cp_a], from: :outline, into: :main)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.ttf")
        stitcher.write_to(path, format: :ttf, subfont: :main)

        loaded = Fontisan::FontLoader.load(path)
        cmap = loaded.table("cmap").unicode_mappings

        # cp_a must remain in the cmap. Without the Layer#add raise-on-
        # conflict contract + UniqueGlyphName deconfliction, the CBDT
        # placeholder at "gid1" would overwrite the outline glyph at
        # "gid1" and cp_a would silently disappear.
        expect(cmap).to include(cp_a),
                        "outline glyph's codepoint U+%04X dropped from cmap — " \
                        "CBDT placeholder overwrote it via name collision (regression)" % cp_a

        # And it must map to the outline glyph (width 500), proving the
        # outline won — not to the CBDT placeholder (width 1000 from
        # CbdtFixture's hmtx).
        hmtx = loaded.table("hmtx")
        hhea = loaded.table("hhea")
        maxp_t = loaded.table("maxp")
        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)
        gid = cmap[cp_a]
        metric = hmtx.metric_for(gid)
        expect(metric[:advance_width]).to eq(500),
                                          "cp_a mapped to CBDT placeholder (width 1000) " \
                                          "instead of outline glyph (width 500) — overwrite regression"
      end
    end
  end
end
