# frozen_string: true

require "spec_helper"
require_relative "../../../lib/fontisan/stitcher/glyph_copier"
require_relative "../../../lib/fontisan/stitcher/deduplicator"

RSpec.describe Fontisan::Stitcher::GlyphCopier do
  let(:ufo) { Fontisan::Ufo }
  # Fake source that returns glyphs from an in-memory hash keyed by gid.
  # Real Source is hard to construct without a loaded TTF — this is a
  # real class (subclass) with overridden behavior, not a double.
  let(:source_class) do
    Class.new(Fontisan::Stitcher::Source) do
      def initialize(glyphs_by_gid)
        @glyphs_by_gid = glyphs_by_gid
        super(nil)
      end

      def glyph_for_gid(gid)
        @glyphs_by_gid[gid]
      end
    end
  end
  let(:deduplicator) { Fontisan::Stitcher::Deduplicator.new }

  def make_glyph(name, cp = nil, width = 500)
    g = ufo::Glyph.new(name: name)
    g.width = width
    g.add_unicode(cp) if cp
    g.add_contour(ufo::Contour.new([
                                     ufo::Point.new(x: 0, y: 0, type: "line"),
                                     ufo::Point.new(x: width, y: 0,
                                                    type: "line"),
                                     ufo::Point.new(x: width, y: 100,
                                                    type: "line"),
                                   ]))
    g
  end

  describe "#inject_notdef" do
    it "creates an empty .notdef when no binding has donor_gid 0" do
      target = ufo::Font.new
      copier = described_class.new(nil)
      copier.inject_notdef([], target)
      expect(target.glyphs.key?(".notdef")).to be(true)
      expect(target.glyphs[".notdef"].contours).to be_empty
    end

    it "copies .notdef from the source when a donor_gid 0 binding exists" do
      source_notdef = make_glyph(".notdef", nil, 600)
      source = source_class.new({ 0 => source_notdef })
      bindings = [{ codepoint: nil, source: source, donor_gid: 0 }]

      target = ufo::Font.new
      copier = described_class.new(nil)
      copier.inject_notdef(bindings, target)

      expect(target.glyphs[".notdef"].width).to eq(600)
    end

    it "registers .notdef with the deduplicator" do
      target = ufo::Font.new
      copier = described_class.new(deduplicator)
      copier.inject_notdef([], target)

      expect(deduplicator.find(target.glyphs[".notdef"])).to eq(".notdef")
    end
  end

  describe "#copy_outlines" do
    it "copies outline glyphs in sorted binding order" do
      g1 = make_glyph("A", 0x41, 500)
      g2 = make_glyph("B", 0x42, 600)
      source = source_class.new({ 1 => g1, 2 => g2 })
      bindings = [
        { codepoint: 0x42, source: source, donor_gid: 2 },
        { codepoint: 0x41, source: source, donor_gid: 1 },
      ]

      target = ufo::Font.new
      target.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
      copier = described_class.new(nil)
      copier.copy_outlines(bindings, target)

      # Sorted by codepoint: 0x41 (gid 1) first, then 0x42 (gid 2).
      expect(target.glyphs.keys).to eq([".notdef", "A", "B"])
    end

    it "skips bindings whose source is in skip_sources" do
      g1 = make_glyph("A", 0x41, 500)
      g2 = make_glyph("B", 0x42, 600)
      source_a = source_class.new({ 1 => g1 })
      source_b = source_class.new({ 1 => g2 })
      bindings = [
        { codepoint: 0x41, source: source_a, donor_gid: 1 },
        { codepoint: 0x42, source: source_b, donor_gid: 1 },
      ]

      target = ufo::Font.new
      target.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
      copier = described_class.new(nil)
      copier.copy_outlines(bindings, target, skip_sources: [source_b])

      expect(target.glyphs.keys).to contain_exactly(".notdef", "A")
    end

    it "skips bindings with donor_gid 0 (already handled by inject_notdef)" do
      g1 = make_glyph(".notdef", nil, 600)
      source = source_class.new({ 0 => g1 })
      bindings = [{ codepoint: nil, source: source, donor_gid: 0 }]

      target = ufo::Font.new
      target.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
      copier = described_class.new(nil)
      copier.copy_outlines(bindings, target)

      expect(target.glyphs.keys).to eq([".notdef"])
    end

    it "deduplicates visually identical glyphs and adds extra unicodes" do
      g1 = make_glyph("A", 0x41, 500)
      g2 = make_glyph("A.dup", 0x41, 500) # same signature
      source = source_class.new({ 1 => g1, 2 => g2 })
      bindings = [
        { codepoint: 0x41, source: source, donor_gid: 1 },
        { codepoint: 0x42, source: source, donor_gid: 2 }, # same outline
      ]

      target = ufo::Font.new
      target.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
      copier = described_class.new(deduplicator)
      copier.copy_outlines(bindings, target)

      # Both codepoints share the same glyph (dedup'd).
      expect(target.glyphs.size).to eq(2) # .notdef + A
      expect(target.glyphs["A"].unicodes).to contain_exactly(0x41, 0x42)
    end

    it "renames glyphs when target already has a glyph with the same name" do
      g1 = make_glyph("A", 0x41, 500)
      source = source_class.new({ 1 => g1 })
      bindings = [{ codepoint: 0x41, source: source, donor_gid: 1 }]

      target = ufo::Font.new
      target.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")
      target.glyphs["A"] = ufo::Glyph.new(name: "A") # pre-existing

      copier = described_class.new(nil)
      copier.copy_outlines(bindings, target)

      expect(target.glyphs.keys).to contain_exactly(".notdef", "A", "A.1")
    end
  end
end
