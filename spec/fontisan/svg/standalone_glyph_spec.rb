# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg"

RSpec.describe Fontisan::Svg::StandaloneGlyph do
  let(:renderer) do
    described_class.new(units_per_em: 1000, ascent: 800, descent: -200)
  end

  def make_glyph(name:, contours: [])
    g = Fontisan::Ufo::Glyph.new(name: name)
    contours.each { |c| g.add_contour(c) }
    g
  end

  def make_point(x, y, type: "line")
    Fontisan::Ufo::Point.new(x: x, y: y, type: type)
  end

  describe "#generate" do
    it "emits a standalone svg root with viewBox" do
      glyph = make_glyph(name: "empty")
      svg = renderer.generate(glyph)

      expect(svg).to include('<?xml version="1.0"')
      expect(svg).to match(%r{<svg[^>]*viewBox="[^"]+">})
      expect(svg).to include("</svg>")
    end

    it "emits a move + lines + close for a simple line contour" do
      contour = Fontisan::Ufo::Contour.new([
                                             make_point(0, 0),
                                             make_point(100, 0),
                                             make_point(100, 100),
                                           ])
      glyph = make_glyph(name: "square", contours: [contour])

      svg = renderer.generate(glyph)
      # Ascent 800 flips Y: 0 → 800, 100 → 700. Use regex to allow
      # either integer or float output (flip_y returns float).
      expect(svg).to match(%r{d="M 0 800(?:\.0)? L 100 800(?:\.0)? L 100 700(?:\.0)? Z"})
    end

    it "emits a quadratic Bezier for one off-curve between on-curves" do
      contour = Fontisan::Ufo::Contour.new([
                                             make_point(0, 0),
                                             make_point(50, 100,
                                                        type: "offcurve"),
                                             make_point(100, 0),
                                           ])
      glyph = make_glyph(name: "curve", contours: [contour])

      svg = renderer.generate(glyph)
      # Off-curve at (50, 100) → flipped Y = 800 - 100 = 700.
      # End on-curve at (100, 0) → flipped Y = 800.
      expect(svg).to match(/Q 50 700(?:\.0)? 100 800(?:\.0)?/)
    end

    it "emits a cubic Bezier for two off-curves between on-curves" do
      contour = Fontisan::Ufo::Contour.new([
                                             make_point(0, 0),
                                             make_point(33, 100,
                                                        type: "offcurve"),
                                             make_point(66, 100,
                                                        type: "offcurve"),
                                             make_point(100, 0),
                                           ])
      glyph = make_glyph(name: "cubic", contours: [contour])

      svg = renderer.generate(glyph)
      expect(svg).to match(/C 33 700(?:\.0)? 66 700(?:\.0)? 100 800(?:\.0)?/)
    end

    it "scales the viewBox to the glyph's bounding box" do
      contour = Fontisan::Ufo::Contour.new([
                                             make_point(50, 50),
                                             make_point(150, 50),
                                             make_point(150, 150),
                                             make_point(50, 150),
                                           ])
      glyph = make_glyph(name: "bbox", contours: [contour])

      svg = renderer.generate(glyph)
      # bbox is x:[50,150], y:[50,150] → viewBox "50 50 100 100"
      expect(svg).to include('viewBox="50 50 100 100"')
    end

    it "emits an empty path for a glyph with no contours" do
      glyph = make_glyph(name: "blank")
      svg = renderer.generate(glyph)
      expect(svg).to include('d=""')
    end

    it "joins multiple contours with spaces" do
      c1 = Fontisan::Ufo::Contour.new([make_point(0, 0), make_point(10, 0)])
      c2 = Fontisan::Ufo::Contour.new([make_point(50, 50), make_point(60, 50)])
      glyph = make_glyph(name: "two", contours: [c1, c2])

      svg = renderer.generate(glyph)
      # Two paths concatenated by space — each ends with Z.
      expect(svg.scan("Z").size).to eq(2)
    end
  end
end
