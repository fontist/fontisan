# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/filters"

RSpec.describe Fontisan::Ufo::Compile::Filters::RemoveOverlaps do
  def square(x_min:, y_min:, size:)
    Fontisan::Ufo::Contour.new([
                                 Fontisan::Ufo::Point.new(x: x_min, y: y_min,
                                                          type: "line"),
                                 Fontisan::Ufo::Point.new(x: x_min + size,
                                                          y: y_min, type: "line"),
                                 Fontisan::Ufo::Point.new(x: x_min + size,
                                                          y: y_min + size, type: "line"),
                                 Fontisan::Ufo::Point.new(x: x_min,
                                                          y: y_min + size, type: "line"),
                               ])
  end

  describe ".run" do
    it "drops a contour whose bbox is fully contained in another" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(square(x_min: 0, y_min: 0, size: 100))
      glyph.add_contour(square(x_min: 25, y_min: 25, size: 50))

      described_class.run([glyph])

      expect(glyph.contours.size).to eq(1)
      expect(glyph.contours.first.points.first.x).to eq(0) # outer remains
    end

    it "preserves contours that partially overlap" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(square(x_min: 0, y_min: 0, size: 100))
      glyph.add_contour(square(x_min: 50, y_min: 50, size: 100)) # overlaps but not contained

      described_class.run([glyph])

      expect(glyph.contours.size).to eq(2)
    end

    it "preserves glyphs with a single contour" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(square(x_min: 0, y_min: 0, size: 100))

      described_class.run([glyph])

      expect(glyph.contours.size).to eq(1)
    end

    it "preserves glyphs with no contours" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      expect { described_class.run([glyph]) }.not_to raise_error
      expect(glyph.contours.size).to eq(0)
    end

    it "does not drop a contained contour with more points than its container" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      outer = Fontisan::Ufo::Contour.new([
                                           Fontisan::Ufo::Point.new(x: 0, y: 0,
                                                                    type: "line"),
                                           Fontisan::Ufo::Point.new(x: 100,
                                                                    y: 0, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 100,
                                                                    y: 100, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 0,
                                                                    y: 100, type: "line"),
                                         ])
      # Inner has 6 points (more than outer's 4) — should be
      # preserved even though its bbox is contained.
      inner = Fontisan::Ufo::Contour.new([
                                           Fontisan::Ufo::Point.new(x: 25,
                                                                    y: 25, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 50,
                                                                    y: 25, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 75,
                                                                    y: 25, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 75,
                                                                    y: 75, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 50,
                                                                    y: 75, type: "line"),
                                           Fontisan::Ufo::Point.new(x: 25,
                                                                    y: 75, type: "line"),
                                         ])
      glyph.add_contour(outer)
      glyph.add_contour(inner)

      described_class.run([glyph])

      expect(glyph.contours.size).to eq(2)
    end

    it "returns the same glyph array (mutates in place)" do
      glyph = Fontisan::Ufo::Glyph.new(name: "g")
      glyph.add_contour(square(x_min: 0, y_min: 0, size: 100))
      glyphs = [glyph]
      result = described_class.run(glyphs)
      expect(result).to equal(glyphs)
    end
  end

  describe "Filters::REGISTRY" do
    it "registers RemoveOverlaps under :remove_overlaps" do
      expect(Fontisan::Ufo::Compile::Filters::REGISTRY[:remove_overlaps])
        .to eq(described_class)
    end
  end
end
