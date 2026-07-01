# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::GlyphSignature do
  let(:ufo) { Fontisan::Ufo }

  def make_glyph(name:, width: 500, contours: [], components: [])
    g = ufo::Glyph.new(name: name)
    g.width = width
    contours.each { |c| g.add_contour(c) }
    components.each { |c| g.add_component(c) }
    g
  end

  def make_contour(points)
    ufo::Contour.new(points.map do |x, y, type|
      ufo::Point.new(x: x, y: y, type: type)
    end)
  end

  describe ".for" do
    it "returns the same signature for identical glyphs" do
      contour = make_contour([[0, 0, "line"], [100, 0, "line"], [100, 100, "line"]])
      a = make_glyph(name: "A", contours: [contour])
      b = make_glyph(name: "B", contours: [make_contour([[0, 0, "line"], [100, 0, "line"], [100, 100, "line"]])])
      expect(described_class.for(a)).to eq(described_class.for(b))
    end

    it "returns different signatures for different outlines" do
      a = make_glyph(name: "A", contours: [make_contour([[0, 0, "line"], [100, 0, "line"]])])
      b = make_glyph(name: "B", contours: [make_contour([[0, 0, "line"], [200, 0, "line"]])])
      expect(described_class.for(a)).not_to eq(described_class.for(b))
    end

    it "returns different signatures for different widths" do
      contour = make_contour([[0, 0, "line"], [100, 0, "line"]])
      a = make_glyph(name: "A", width: 500, contours: [contour])
      b = make_glyph(name: "B", width: 600, contours: [make_contour([[0, 0, "line"], [100, 0, "line"]])])
      expect(described_class.for(a)).not_to eq(described_class.for(b))
    end

    it "returns different signatures for different point types" do
      a = make_glyph(name: "A", contours: [make_contour([[0, 0, "line"], [100, 0, "offcurve"]])])
      b = make_glyph(name: "B", contours: [make_contour([[0, 0, "line"], [100, 0, "curve"]])])
      expect(described_class.for(a)).not_to eq(described_class.for(b))
    end

    it "returns different signatures when components differ" do
      comp_a = ufo::Component.new(base_glyph: "base1")
      comp_b = ufo::Component.new(base_glyph: "base2")
      a = make_glyph(name: "A", components: [comp_a])
      b = make_glyph(name: "B", components: [comp_b])
      expect(described_class.for(a)).not_to eq(described_class.for(b))
    end

    it "treats empty glyphs (no contours) with same width as identical" do
      a = make_glyph(name: "space", width: 250)
      b = make_glyph(name: "space2", width: 250)
      expect(described_class.for(a)).to eq(described_class.for(b))
    end

    it "is deterministic (same glyph → same signature across calls)" do
      g = make_glyph(name: "X", contours: [make_contour([[1, 2, "line"], [3, 4, "line"]])])
      sig1 = described_class.for(g)
      sig2 = described_class.for(make_glyph(name: "X2", contours: [make_contour([[1, 2, "line"], [3, 4, "line"]])]))
      expect(sig1).to eq(sig2)
    end
  end
end
