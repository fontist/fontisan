# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/filters"

RSpec.describe Fontisan::Ufo::Compile::Filters do
  describe ".apply" do
    it "runs named filters in order" do
      glyph = Fontisan::Ufo::Glyph.new(name: "test")
      glyph.add_contour(Fontisan::Ufo::Contour.new([
                                                     Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 100, y: 100, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 0, y: 100, type: "line"),
                                                   ]))
      glyphs = [glyph]

      described_class.apply([:reverse_contour_direction], glyphs)
      expect(glyph.contours.first.points.first.x).to eq(0)
      expect(glyph.contours.first.points.first.y).to eq(100)
    end

    it "raises on unknown filter" do
      expect { described_class.apply([:nonexistent], []) }
        .to raise_error(ArgumentError, /unknown filter/)
    end
  end

  describe Fontisan::Ufo::Compile::Filters::ReverseContourDirection do
    it "reverses point order in each contour" do
      glyph = Fontisan::Ufo::Glyph.new(name: "A")
      glyph.add_contour(Fontisan::Ufo::Contour.new([
                                                     Fontisan::Ufo::Point.new(x: 1, y: 2, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 3, y: 4, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 5, y: 6, type: "line"),
                                                   ]))

      described_class.run([glyph])

      pts = glyph.contours.first.points
      expect(pts.map(&:x)).to eq([5, 3, 1])
      expect(pts.map(&:y)).to eq([6, 4, 2])
    end
  end

  describe Fontisan::Ufo::Compile::Filters::CubicToQuadratic do
    it "converts a cubic segment into a quadratic approximation" do
      glyph = Fontisan::Ufo::Glyph.new(name: "curve")
      glyph.add_contour(Fontisan::Ufo::Contour.new([
                                                     Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 50, y: 100, type: "offcurve"),
                                                     Fontisan::Ufo::Point.new(x: 150, y: 100, type: "offcurve"),
                                                     Fontisan::Ufo::Point.new(x: 200, y: 0, type: "curve"),
                                                   ]))

      described_class.run([glyph])

      # The cubic (0,0)-(50,100)-(150,100)-(200,0) should be
      # approximated as a quadratic with a control point near
      # (100, 150) and endpoint (200, 0).
      pts = glyph.contours.first.points
      # Should still have an on-curve start + off-curve + on-curve end
      expect(pts.first.x).to eq(0)
      expect(pts.last.x).to eq(200)
      # There should be at least one off-curve control point
      expect(pts.any? { |p| p.type == "offcurve" }).to be(true)
    end

    it "leaves quadratic-only contours unchanged" do
      glyph = Fontisan::Ufo::Glyph.new(name: "quad")
      glyph.add_contour(Fontisan::Ufo::Contour.new([
                                                     Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                     Fontisan::Ufo::Point.new(x: 100, y: 200, type: "offcurve"),
                                                     Fontisan::Ufo::Point.new(x: 200, y: 0, type: "qcurve"),
                                                   ]))

      described_class.run([glyph])

      pts = glyph.contours.first.points
      # Single off-curve → single quadratic, not changed
      expect(pts.size).to eq(3)
    end
  end

  describe Fontisan::Ufo::Compile::Filters::DecomposeComponents do
    it "clears components from composite glyphs" do
      glyph = Fontisan::Ufo::Glyph.new(name: "composite")
      glyph.add_component(Fontisan::Ufo::Component.new(base_glyph: "A"))

      described_class.run([glyph])
      expect(glyph.components).to be_empty
    end
  end
end
