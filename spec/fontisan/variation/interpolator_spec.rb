# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/interpolator"

RSpec.describe Fontisan::Variation::Interpolator do
  let(:axes) do
    [
      double(
        "VariationAxisRecord",
        axis_tag: "wght",
        min_value: 400.0,
        default_value: 600.0,
        max_value: 900.0
      ),
      double(
        "VariationAxisRecord",
        axis_tag: "wdth",
        min_value: 75.0,
        default_value: 100.0,
        max_value: 125.0
      ),
    ]
  end

  describe "#initialize" do
    it "creates an interpolator with axes" do
      interpolator = described_class.new(axes)
      expect(interpolator.axes).to eq(axes)
    end

    it "handles nil axes" do
      interpolator = described_class.new(nil)
      expect(interpolator.axes).to eq([])
    end
  end

  describe "#normalize_coordinate" do
    let(:interpolator) { described_class.new(axes) }

    context "with weight axis" do
      it "normalizes value below default" do
        result = interpolator.normalize_coordinate(500.0, "wght")
        # (500 - 600) / (600 - 400) = -0.5
        expect(result).to be_within(0.01).of(-0.5)
      end

      it "normalizes value above default" do
        result = interpolator.normalize_coordinate(750.0, "wght")
        # (750 - 600) / (900 - 600) = 0.5
        expect(result).to be_within(0.01).of(0.5)
      end

      it "normalizes default to zero" do
        result = interpolator.normalize_coordinate(600.0, "wght")
        expect(result).to eq(0.0)
      end

      it "clamps to -1 at minimum" do
        result = interpolator.normalize_coordinate(400.0, "wght")
        expect(result).to eq(-1.0)
      end

      it "clamps to 1 at maximum" do
        result = interpolator.normalize_coordinate(900.0, "wght")
        expect(result).to eq(1.0)
      end

      it "clamps values outside range" do
        result = interpolator.normalize_coordinate(1000.0, "wght")
        expect(result).to eq(1.0)

        result = interpolator.normalize_coordinate(300.0, "wght")
        expect(result).to eq(-1.0)
      end
    end

    it "returns 0 for unknown axis" do
      result = interpolator.normalize_coordinate(500.0, "unknown")
      expect(result).to eq(0.0)
    end
  end

  describe "#normalize_coordinates" do
    let(:interpolator) { described_class.new(axes) }

    it "normalizes all coordinates" do
      coordinates = { "wght" => 750.0, "wdth" => 112.5 }

      result = interpolator.normalize_coordinates(coordinates)

      expect(result["wght"]).to be_within(0.01).of(0.5)
      expect(result["wdth"]).to be_within(0.01).of(0.5)
    end

    it "uses default values for missing coordinates" do
      coordinates = { "wght" => 750.0 }

      result = interpolator.normalize_coordinates(coordinates)

      expect(result["wght"]).to be_within(0.01).of(0.5)
      expect(result["wdth"]).to eq(0.0) # Default value
    end
  end

  describe "#calculate_axis_scalar" do
    let(:interpolator) { described_class.new(axes) }

    it "calculates scalar between start and peak" do
      region = { start: -1.0, peak: 0.0, end: 1.0 }
      coord = -0.5

      scalar = interpolator.calculate_axis_scalar(coord, region)

      # (-0.5 - (-1.0)) / (0.0 - (-1.0)) = 0.5
      expect(scalar).to be_within(0.01).of(0.5)
    end

    it "calculates scalar between peak and end" do
      region = { start: -1.0, peak: 0.0, end: 1.0 }
      coord = 0.5

      scalar = interpolator.calculate_axis_scalar(coord, region)

      # (1.0 - 0.5) / (1.0 - 0.0) = 0.5
      expect(scalar).to be_within(0.01).of(0.5)
    end

    it "returns 1.0 at peak" do
      region = { start: -1.0, peak: 0.5, end: 1.0 }
      coord = 0.5

      scalar = interpolator.calculate_axis_scalar(coord, region)

      expect(scalar).to eq(1.0)
    end

    it "returns 0.0 outside region" do
      region = { start: 0.0, peak: 0.5, end: 1.0 }

      scalar = interpolator.calculate_axis_scalar(-0.5, region)
      expect(scalar).to eq(0.0)

      scalar = interpolator.calculate_axis_scalar(1.5, region)
      expect(scalar).to eq(0.0)
    end
  end

  describe "#calculate_region_scalar" do
    let(:interpolator) { described_class.new(axes) }

    it "multiplies scalars for multi-axis region" do
      region = {
        "wght" => { start: -1.0, peak: 0.0, end: 1.0 },
        "wdth" => { start: -1.0, peak: 0.0, end: 1.0 },
      }
      coordinates = { "wght" => -0.5, "wdth" => -0.5 }

      scalar = interpolator.calculate_region_scalar(coordinates, region)

      # 0.5 * 0.5 = 0.25
      expect(scalar).to be_within(0.01).of(0.25)
    end

    it "returns 0 if any axis is outside region" do
      region = {
        "wght" => { start: 0.0, peak: 0.5, end: 1.0 },
        "wdth" => { start: 0.0, peak: 0.5, end: 1.0 },
      }
      coordinates = { "wght" => 0.5, "wdth" => -0.5 } # wdth outside

      scalar = interpolator.calculate_region_scalar(coordinates, region)

      expect(scalar).to eq(0.0)
    end
  end

  describe "#interpolate_value" do
    let(:interpolator) { described_class.new(axes) }

    it "interpolates with deltas and scalars" do
      base = 100.0
      deltas = [10.0, 20.0]
      scalars = [0.5, 0.8]

      result = interpolator.interpolate_value(base, deltas, scalars)

      # 100 + (10 * 0.5) + (20 * 0.8) = 121.0
      expect(result).to be_within(0.01).of(121.0)
    end

    it "returns base value with zero scalars" do
      base = 100.0
      deltas = [10.0, 20.0]
      scalars = [0.0, 0.0]

      result = interpolator.interpolate_value(base, deltas, scalars)

      expect(result).to eq(100.0)
    end
  end

  describe "#interpolate_point" do
    let(:interpolator) { described_class.new(axes) }

    it "interpolates x and y coordinates" do
      base_point = { x: 100.0, y: 200.0 }
      delta_points = [
        { x: 10.0, y: 20.0 },
        { x: 5.0, y: 10.0 },
      ]
      scalars = [0.5, 0.8]

      result = interpolator.interpolate_point(base_point, delta_points, scalars)

      # x: 100 + (10 * 0.5) + (5 * 0.8) = 109.0
      # y: 200 + (20 * 0.5) + (10 * 0.8) = 218.0
      expect(result[:x]).to be_within(0.01).of(109.0)
      expect(result[:y]).to be_within(0.01).of(218.0)
    end
  end

  describe "#build_region_from_tuple" do
    let(:interpolator) { described_class.new(axes) }

    it "builds region from tuple data" do
      tuple = {
        peak: [0.5, -0.3],
        start: [-1.0, -1.0],
        end: [1.0, 1.0],
      }

      region = interpolator.build_region_from_tuple(tuple)

      expect(region["wght"][:peak]).to eq(0.5)
      expect(region["wght"][:start]).to eq(-1.0)
      expect(region["wght"][:end]).to eq(1.0)
      expect(region["wdth"][:peak]).to eq(-0.3)
    end

    it "handles missing start/end in tuple" do
      tuple = {
        peak: [0.5, -0.3],
      }

      region = interpolator.build_region_from_tuple(tuple)

      expect(region["wght"][:start]).to eq(-1.0)
      expect(region["wght"][:end]).to eq(1.0)
    end
  end
end
