# frozen_string: true

require "spec_helper"
require_relative "../../../lib/fontisan/stitcher"
require_relative "../../support/cbdt_fixture"
require "tmpdir"

# Regression coverage for the CBDT-placeholder-overwrites-outline bug.
#
# Before the Layer#add contract was tightened (raise-on-conflict +
# UniqueGlyphName helper), CbdtPropagator#add_placeholder_glyphs named
# its placeholders "gid{N}" — the SAME scheme Source#extract_truetype_glyph
# uses for outline glyphs from TTF donors. When both an outline donor
# and a CBDT donor contributed to the same target, Layer#add silently
# hash-overwrote the outline glyph with the empty placeholder. The
# outline's codepoints dropped out of the cmap; CJK Ext G in
# Essenfont-Regular.ttc lost 3,917 of 4,939 codepoints this way.
#
# This spec reproduces the failure mode minimally: an outline donor
# whose U+30F4D sits at gid 4027, plus a CBDT source whose glyph
# count is high enough that its placeholders cover "gid4027". Without
# the fix, the placeholder overwrites the outline glyph and U+30F4D
# disappears from the cmap.
RSpec.describe Fontisan::Stitcher, "CBDT placeholder vs outline glyph naming" do
  let(:ufo) { Fontisan::Ufo }

  # Build a small UFO outline donor covering one codepoint, with the
  # glyph at a known position. Naming is delegated to the compiler;
  # all we need is a real outline glyph at GID 1 covering shared_cp.
  def make_outline_source_with(name, cp, width: 500)
    font = ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

    g = ufo::Glyph.new(name: name)
    g.width = width
    g.add_unicode(cp)
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: width, y: 0, type: "line"),
                                     ufo::Point.new(x: width, y: 100, type: "line"),
                                   ]))
    font.glyphs[name] = g
    font
  end

  it "outline glyph wins cmap mapping; CBDT placeholder lands at its own GID" do
    shared_cp = 0x1F600
    outline = make_outline_source_with("outline-emoji", shared_cp, width: 500)

    cbdt_dir = Dir.mktmpdir
    cbdt_path = File.join(cbdt_dir, "cbdt.ttf")
    Fontisan::SpecHelpers::CbdtFixture.write_font(codepoints: [shared_cp], path: cbdt_path)
    cbdt_font = Fontisan::FontLoader.load(cbdt_path)

    stitcher = described_class.new
    stitcher.add_source(:outline, outline)
    stitcher.add_source(:cbdt, cbdt_font)
    stitcher.include_notdef(from: :outline, into: :main)
    stitcher.include_codepoints([shared_cp], from: :outline, into: :main)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.ttf")
      stitcher.write_to(path, format: :ttf, subfont: :main)

      loaded = Fontisan::FontLoader.load(path)
      cmap = loaded.table("cmap").unicode_mappings

      # The shared codepoint must remain in the cmap. Before the fix,
      # the CBDT placeholder named "gid{N}" (where N matched the outline
      # glyph's donor gid) overwrote the outline glyph and the cp was
      # silently dropped.
      expect(cmap).to include(shared_cp),
                      "shared codepoint U+%06X dropped from cmap — CBDT placeholder " \
                      "overwrote the outline glyph (regression)" % shared_cp

      # And it must map to the outline glyph (width 500), proving the
      # outline won over the empty placeholder.
      hmtx = loaded.table("hmtx")
      hhea = loaded.table("hhea")
      maxp_t = loaded.table("maxp")
      hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)
      gid = cmap[shared_cp]
      metric = hmtx.metric_for(gid)
      expect(metric[:advance_width]).to eq(500),
                                        "shared codepoint mapped to CBDT placeholder (width 1000) " \
                                        "instead of outline glyph (width 500) — overwrite regression"
    end
  end
end
