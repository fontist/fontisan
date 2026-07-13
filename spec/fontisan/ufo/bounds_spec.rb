# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Ufo::Bounds do
  describe ".measure" do
    it "computes the bounding box of contour points" do
      contours = [
        Fontisan::Ufo::Contour.new([
                                     Fontisan::Ufo::Point.new(x: 100, y: 200, type: "line"),
                                     Fontisan::Ufo::Point.new(x: 300, y: 400, type: "line"),
                                   ]),
        Fontisan::Ufo::Contour.new([
                                     Fontisan::Ufo::Point.new(x: 50, y: 600, type: "line"),
                                     Fontisan::Ufo::Point.new(x: 500, y: 50, type: "line"),
                                   ]),
      ]

      bounds = described_class.measure(contours)
      expect(bounds.min_x).to eq(50)
      expect(bounds.min_y).to eq(50)
      expect(bounds.max_x).to eq(500)
      expect(bounds.max_y).to eq(600)
    end

    it "returns empty bounds for no contours" do
      expect(described_class.measure([])).to eq(described_class.empty)
    end

    it "returns empty bounds for contours with no points" do
      contours = [Fontisan::Ufo::Contour.new([])]
      expect(described_class.measure(contours)).to eq(described_class.empty)
    end

    it "handles negative coordinates" do
      contours = [
        Fontisan::Ufo::Contour.new([
                                     Fontisan::Ufo::Point.new(x: -100, y: -200, type: "line"),
                                     Fontisan::Ufo::Point.new(x: 300, y: -50, type: "line"),
                                   ]),
      ]

      bounds = described_class.measure(contours)
      expect(bounds.min_x).to eq(-100)
      expect(bounds.min_y).to eq(-200)
      expect(bounds.max_x).to eq(300)
      expect(bounds.max_y).to eq(-50)
    end

    it "iterates contours lazily without allocating a flat points array" do
      enumerator = Enumerator.new do |y|
        y << Fontisan::Ufo::Contour.new([
                                          Fontisan::Ufo::Point.new(x: 10, y: 20, type: "line"),
                                          Fontisan::Ufo::Point.new(x: 30, y: 40, type: "line"),
                                        ])
      end

      bounds = described_class.measure(enumerator)
      expect(bounds.min_x).to eq(10)
      expect(bounds.max_y).to eq(40)
    end

    it "includes off-curve control points in the measurement" do
      # A cubic Bezier with control points outside the visible curve:
      # the curve from (100,0) to (200,0) with controls (100,500) and (200,500)
      # has visible extent y ∈ [0, ~225] but control points reach y=500.
      # Bounds measures raw point extents, not curve extents.
      contours = [
        Fontisan::Ufo::Contour.new([
                                     Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                     Fontisan::Ufo::Point.new(x: 100, y: 500, type: "offcurve"),
                                     Fontisan::Ufo::Point.new(x: 200, y: 500, type: "offcurve"),
                                     Fontisan::Ufo::Point.new(x: 200, y: 0, type: "curve"),
                                   ]),
      ]

      bounds = described_class.measure(contours)
      expect(bounds.max_y).to eq(500)
    end
  end

  describe ".empty" do
    it "returns bounds at the origin with zero extent" do
      bounds = described_class.empty
      expect(bounds.min_x).to eq(0)
      expect(bounds.min_y).to eq(0)
      expect(bounds.max_x).to eq(0)
      expect(bounds.max_y).to eq(0)
      expect(bounds).to be_empty
    end
  end

  describe "#width and #height" do
    it "computes extent from min/max pairs" do
      bounds = described_class.new(min_x: 10, min_y: 20, max_x: 110, max_y: 270)
      expect(bounds.width).to eq(100)
      expect(bounds.height).to eq(250)
    end

    it "reports zero extent for a single-point contour's bounds" do
      bounds = described_class.new(min_x: 50, min_y: 50, max_x: 50, max_y: 50)
      expect(bounds.width).to eq(0)
      expect(bounds.height).to eq(0)
      expect(bounds).to be_empty
    end
  end

  describe "#union" do
    it "returns the smallest bounds containing both inputs" do
      a = described_class.new(min_x: 0, min_y: 0, max_x: 100, max_y: 50)
      b = described_class.new(min_x: -50, min_y: 25, max_x: 50, max_y: 200)

      unioned = a.union(b)
      expect(unioned.min_x).to eq(-50)
      expect(unioned.min_y).to eq(0)
      expect(unioned.max_x).to eq(100)
      expect(unioned.max_y).to eq(200)
    end

    it "is reflexive: a.union(b) == b.union(a)" do
      a = described_class.new(min_x: 0, min_y: 0, max_x: 100, max_y: 50)
      b = described_class.new(min_x: -50, min_y: 25, max_x: 50, max_y: 200)

      expect(a.union(b)).to eq(b.union(a))
    end

    it "returns empty when given two empty bounds" do
      expect(described_class.empty.union(described_class.empty)).to eq(described_class.empty)
    end
  end

  describe "value semantics" do
    it "equals another bounds with the same coordinates" do
      a = described_class.new(min_x: 1, min_y: 2, max_x: 3, max_y: 4)
      b = described_class.new(min_x: 1, min_y: 2, max_x: 3, max_y: 4)
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "is comparable via the four-coordinate lex order" do
      a = described_class.new(min_x: 0, min_y: 0, max_x: 10, max_y: 10)
      b = described_class.new(min_x: 1, min_y: 0, max_x: 10, max_y: 10)
      expect(a < b).to be(true)
    end
  end
end
