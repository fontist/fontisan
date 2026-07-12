# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::SvgToGlyf::Path::Bounds do
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
      bounds = described_class.measure([])
      expect(bounds).to be_empty
    end

    it "returns empty bounds for contours with no points" do
      contours = [Fontisan::Ufo::Contour.new([])]
      bounds = described_class.measure(contours)
      expect(bounds).to be_empty
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
  end

  describe "#width and #height" do
    it "computes width and height from the bounding box" do
      bounds = described_class.new(min_x: 10, min_y: 20, max_x: 110, max_y: 270)
      expect(bounds.width).to eq(100)
      expect(bounds.height).to eq(250)
    end
  end

  describe "#empty?" do
    it "is true for zero-extent bounds" do
      expect(described_class.empty).to be_empty
    end

    it "is false for non-zero bounds" do
      bounds = described_class.new(min_x: 0, min_y: 0, max_x: 1, max_y: 1)
      expect(bounds).not_to be_empty
    end
  end

  describe ".empty" do
    it "returns bounds at the origin with zero extent" do
      bounds = described_class.empty
      expect(bounds.min_x).to eq(0)
      expect(bounds.min_y).to eq(0)
      expect(bounds.max_x).to eq(0)
      expect(bounds.max_y).to eq(0)
    end
  end
end
