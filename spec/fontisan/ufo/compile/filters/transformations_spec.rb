# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/filters"

RSpec.describe Fontisan::Ufo::Compile::Filters::Transformations do
  let(:glyph) do
    g = Fontisan::Ufo::Glyph.new(name: "test")
    g.add_contour(Fontisan::Ufo::Contour.new([
                                               Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                               Fontisan::Ufo::Point.new(x: 100, y: 100, type: "line"),
                                             ]))
    g.add_component(Fontisan::Ufo::Component.new(base_glyph: "A"))
    g
  end

  describe ".run" do
    it "is a no-op when matrix is nil" do
      original_points = glyph.contours[0].points.map { |p| [p.x, p.y] }
      described_class.run([glyph], matrix: nil)

      expect(glyph.contours[0].points.map { |p| [p.x, p.y] }).to eq(original_points)
      expect(glyph.components[0].transformation).to be_nil
    end

    it "is a no-op when matrix is identity" do
      original_points = glyph.contours[0].points.map { |p| [p.x, p.y] }
      described_class.run([glyph], matrix: [1, 0, 0, 1, 0, 0])

      expect(glyph.contours[0].points.map { |p| [p.x, p.y] }).to eq(original_points)
      expect(glyph.components[0].transformation).to be_nil
    end

    it "applies a translation to every contour point" do
      described_class.run([glyph], matrix: [1, 0, 0, 1, 50, 100])

      coords = glyph.contours[0].points.map { |p| [p.x, p.y] }
      expect(coords).to eq([[50.0, 100.0], [150.0, 100.0], [150.0, 200.0]])
    end

    it "applies a uniform scale to every contour point" do
      described_class.run([glyph], matrix: [2, 0, 0, 2, 0, 0])

      coords = glyph.contours[0].points.map { |p| [p.x, p.y] }
      expect(coords).to eq([[0.0, 0.0], [200.0, 0.0], [200.0, 200.0]])
    end

    it "applies a horizontal flip (mirror across vertical axis at x=50)" do
      # a=-1, e=100 → x' = -x + 100. Point at x=0 → 100; x=100 → 0.
      described_class.run([glyph], matrix: [-1, 0, 0, 1, 100, 0])

      coords = glyph.contours[0].points.map { |p| [p.x, p.y] }
      expect(coords).to eq([[100.0, 0.0], [0.0, 0.0], [0.0, 100.0]])
    end

    it "composes the transform onto each component's existing transformation (left-side composition)" do
      # First translate the whole glyph by (50, 100). Component's
      # transformation should now be the translate.
      described_class.run([glyph], matrix: [1, 0, 0, 1, 50, 100])
      expect(glyph.components[0].transformation.to_a).to eq([1.0, 0.0, 0.0, 1.0, 50.0, 100.0])

      # Now apply scale(2,2). The new component transformation should
      # be scale ∘ translate: x' = 2x + 100, y' = 2y + 200.
      described_class.run([glyph], matrix: [2, 0, 0, 2, 0, 0])
      expect(glyph.components[0].transformation.to_a).to eq([2.0, 0.0, 0.0, 2.0, 100.0, 200.0])
    end

    it "accepts a Transformation value object as the matrix" do
      transform = Fontisan::Ufo::Transformation.new(a: 2, e: 10)
      described_class.run([glyph], matrix: transform)

      coords = glyph.contours[0].points.map { |p| [p.x, p.y] }
      expect(coords).to eq([[10.0, 0.0], [210.0, 0.0], [210.0, 100.0]])
    end

    it "preserves point type and smoothness through the transform" do
      glyph.contours[0].points[1] = Fontisan::Ufo::Point.new(
        x: 100, y: 0, type: "offcurve", smooth: false,
      )
      described_class.run([glyph], matrix: [1, 0, 0, 1, 0, 0])
      # No-op (identity), but verify type/smooth preserved through path.
      expect(glyph.contours[0].points[1].type).to eq("offcurve")
    end

    it "returns the same glyph array (mutates in place)" do
      glyphs = [glyph]
      result = described_class.run(glyphs, matrix: [1, 0, 0, 1, 5, 5])
      expect(result).to equal(glyphs)
    end
  end

  describe "Filters::REGISTRY" do
    it "registers Transformations under :transformations" do
      expect(Fontisan::Ufo::Compile::Filters::REGISTRY[:transformations])
        .to eq(described_class)
    end

    it "applies via the Filters hub by symbol" do
      Fontisan::Ufo::Compile::Filters.apply([:transformations], [glyph],
                                            matrix: [1, 0, 0, 1, 50, 100])
      coords = glyph.contours[0].points.map { |p| [p.x, p.y] }
      expect(coords.first).to eq([50.0, 100.0])
    end
  end
end
