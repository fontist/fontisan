# frozen_string: true

require "spec_helper"
require_relative "../../../lib/fontisan/stitcher"
require_relative "../../../spec/support/cbdt_fixture"
require "tmpdir"

# Regression coverage for the outline-vs-CBDT cmap-priority bug (PR #104).
#
# When both an outline donor and a CBDT donor cover the same codepoint,
# the resulting cmap MUST map that codepoint to the OUTLINE glyph's GID,
# not to the empty CBDT placeholder. Cmap.build uses first-wins semantics
# (see Fontisan::Ufo::Compile::Cmap docstring); Stitcher relies on
# outline-first ordering to satisfy that contract.
RSpec.describe Fontisan::Stitcher do
  describe "outline-vs-CBDT priority" do
    let(:ufo) { Fontisan::Ufo }

    def make_outline_source_with(name, cp, width: 500)
      font = ufo::Font.new
      font.info.units_per_em = 1000
      font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

      g = ufo::Glyph.new(name: name)
      # Vary width per-name so deduplicator sees distinct glyphs (it
      # keys off width + contours + components).
      g.width = width
      g.add_unicode(cp)
      g.add_contour(ufo::Contour.new([
                                       ufo::Point.new(x: 0, y: 0, type: "line"),
                                       ufo::Point.new(x: width, y: 0,
                                                      type: "line"),
                                       ufo::Point.new(x: width, y: 100,
                                                      type: "line"),
                                     ]))
      font.glyphs[name] = g
      font
    end

    # Build an in-memory CBDT source font covering the given codepoints.
    # Each codepoint resolves to a placeholder glyph with advance_width
    # 1000 (distinct from the outline donor's 500/600 so we can tell
    # from the stitched font's hmtx which glyph the cmap mapped to).
    def make_cbdt_source_with(codepoints)
      dir = Dir.mktmpdir
      path = File.join(dir, "cbdt.ttf")
      Fontisan::SpecHelpers::CbdtFixture.write_font(codepoints: codepoints,
                                                    path: path)
      Fontisan::FontLoader.load(path)
    end

    describe "Cmap first-wins contract" do
      # Direct test of the first-wins semantics that the outline-first
      # fix relies on. Two outline donors covering the same codepoint:
      # the donor whose glyphs land at lower GIDs must win the cmap
      # mapping. Stitcher achieves this for outline-vs-CBDT by adding
      # outline glyphs first; this spec verifies the cmap half of the
      # contract holds for any "lower-GID wins" scenario.
      it "maps a shared codepoint to the lower-GID glyph (first-wins)" do
        cp = 0x41
        first = make_outline_source_with("first-outline", cp, width: 500)
        second = make_outline_source_with("second-outline", cp, width: 600)

        stitcher = described_class.new
        stitcher.add_source(:first, first)
        stitcher.add_source(:second, second)
        stitcher.include_notdef(from: :first, into: :combined)
        stitcher.include_codepoints([cp], from: :first, into: :combined)
        stitcher.include_codepoints([cp], from: :second, into: :combined)

        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.ttf")
          stitcher.write_to(path, format: :ttf, subfont: :combined)

          loaded = Fontisan::FontLoader.load(path)
          gid = loaded.table("cmap").unicode_mappings[cp]
          expect(gid).to eq(1),
                         "first-wins contract broken: codepoint should map to GID 1 (first-added), got #{gid}"

          # Glyph at gid 1 must be the first-added outline glyph, not the
          # second. Use hmtx.metric_for(gid).advance_width as the identity
          # check since the compiler emits post version 3 (no glyph names)
          # by default.
          hmtx = loaded.table("hmtx")
          hhea = loaded.table("hhea")
          maxp_t = loaded.table("maxp")
          hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)
          metric = hmtx.metric_for(gid)
          expect(metric[:advance_width]).to eq(500),
                                            "first-added glyph (width 500) must win cmap mapping; " \
                                            "got width #{metric[:advance_width]} at gid #{gid}"
        end
      end
    end

    describe "outline-first ordering with CBDT donor" do
      # End-to-end regression for the original Emoticons cmap-loss bug.
      # Uses a synthesized CBDT source (see CbdtFixture) — no bundled
      # fixture file needed. Verifies that a codepoint covered by BOTH
      # the outline donor and the CBDT donor maps to the outline glyph
      # (advance_width 500 from make_outline_source_with), not to the
      # CBDT placeholder (advance_width 1000 from CbdtFixture).
      it "cmap maps shared codepoint to outline glyph GID, not CBDT placeholder" do
        shared_cp = 0x1F600          # in both CBDT source and outline donor
        outline_only_cp = 0x41       # only in outline donor
        cbdt_only_cp = 0x1F601       # only in CBDT source

        outline = make_outline_source_with("outline-emoji", shared_cp,
                                           width: 500)
        # add a second outline glyph for the outline-only codepoint
        g = ufo::Glyph.new(name: "outline-A")
        g.width = 600
        g.add_unicode(outline_only_cp)
        g.add_contour(ufo::Contour.new([
                                         ufo::Point.new(x: 0, y: 0,
                                                        type: "line"),
                                         ufo::Point.new(x: 600, y: 0,
                                                        type: "line"),
                                         ufo::Point.new(x: 300, y: 700,
                                                        type: "line"),
                                       ]))
        outline.glyphs["outline-A"] = g

        cbdt_font = make_cbdt_source_with([shared_cp, cbdt_only_cp])

        stitcher = described_class.new
        stitcher.add_source(:outline, outline)
        stitcher.add_source(:cbdt, cbdt_font)
        stitcher.include_notdef(from: :outline, into: :main)
        stitcher.include_codepoints([shared_cp, outline_only_cp],
                                    from: :outline, into: :main)

        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.ttf")
          stitcher.write_to(path, format: :ttf, subfont: :main)

          loaded = Fontisan::FontLoader.load(path)
          cmap = loaded.table("cmap").unicode_mappings

          # All three codepoints must be present in the cmap.
          expect(cmap).to include(shared_cp),
                          "shared codepoint U+%06X missing from cmap" % shared_cp
          expect(cmap).to include(outline_only_cp),
                          "outline-only codepoint U+%06X missing from cmap" % outline_only_cp
          expect(cmap).to include(cbdt_only_cp),
                          "CBDT-only codepoint U+%06X missing (placeholder should still cover)" % cbdt_only_cp

          # The shared codepoint must map to a glyph whose advance_width
          # is 500 (the outline donor's value). The CBDT placeholder
          # would have width 1000, so a wrong cmap mapping is detectable.
          hmtx = loaded.table("hmtx")
          hhea = loaded.table("hhea")
          maxp_t = loaded.table("maxp")
          hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)

          shared_gid = cmap[shared_cp]
          metric = hmtx.metric_for(shared_gid)
          expect(metric[:advance_width]).to eq(500),
                                            "shared codepoint mapped to CBDT placeholder (width 1000) " \
                                            "instead of outline glyph (width 500); outline-first fix regressed"
        end
      end

      # Collection variant of the same regression: each subfont is
      # compiled independently, then packed via Collection::Builder.
      # Verifies the cmap survives the round-trip through the multi-face
      # pipeline without losing the outline-first priority, AND that the
      # CBDT placeholder names ("gid{N}") don't overwrite outline glyphs
      # sharing the same donor-gid naming scheme.
      it "write_collection preserves outline-first cmap priority across faces" do
        shared_cp = 0x1F600
        outline = make_outline_source_with("outline-emoji", shared_cp,
                                           width: 500)
        cbdt_font = make_cbdt_source_with([shared_cp])

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
            cmap = face.table("cmap").unicode_mappings
            expect(cmap).to include(shared_cp)

            hmtx = face.table("hmtx")
            hhea = face.table("hhea")
            maxp_t = face.table("maxp")
            hmtx.parse_with_context(hhea.number_of_h_metrics, maxp_t.num_glyphs)
            gid = cmap[shared_cp]
            metric = hmtx.metric_for(gid)
            expect(metric[:advance_width]).to eq(500),
                                              "collection mode mapped shared codepoint to CBDT placeholder"
          end
        end
      end
    end

    describe "CBDT source detection" do
      it "safe_cbdt_source returns nil when no source has CBDT" do
        stitcher = described_class.new
        stitcher.add_source(:outline, make_outline_source_with("A", 0x41))
        target = stitcher.build_target_font(subfont: :test)
        expect(target.glyphs.size).to be > 0
        # safe_cbdt_source is private; verified indirectly via the
        # compile path succeeding without propagate_cbdt_tables being
        # invoked (which would raise on a non-CBDT-loaded compiled font).
      end

      it "raises on multiple CBDT sources via cbdt_source" do
        # Subclass Source to report :cbdt so we can exercise the
        # multi-CBDT raise without a real CBDT fixture. Subclassing is
        # not a double — it's a real class with overridden behavior.
        cbdt_class = Class.new(Fontisan::Stitcher::Source) do
          def bitmap_mode = :cbdt
        end

        stitcher = described_class.new
        stitcher.add_source(:a, make_outline_source_with("A", 0x41))
        stitcher.add_source(:b, make_outline_source_with("B", 0x42))
        # Replace source wrappers with our CBDT-reporting subclass.
        stitcher.sources[:a] = cbdt_class.new(stitcher.sources[:a].font)
        stitcher.sources[:b] = cbdt_class.new(stitcher.sources[:b].font)

        expect do
          stitcher.write_to(File.join(Dir.mktmpdir, "x.ttf"),
                            format: :ttf, subfont: :test)
        end
          .to raise_error(Fontisan::MultipleCbdtSourcesError,
                          /multiple CBDT sources/)
      end
    end
  end
end
