# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg/view_box_calculator"

RSpec.describe Fontisan::Svg::ViewBoxCalculator do
  describe "#initialize" do
    it "creates calculator with valid parameters" do
      calculator = described_class.new(
        units_per_em: 1000,
        ascent: 800,
        descent: -200,
      )

      expect(calculator.units_per_em).to eq(1000)
      expect(calculator.ascent).to eq(800)
      expect(calculator.descent).to eq(-200)
    end

    it "raises error for nil units_per_em" do
      expect do
        described_class.new(units_per_em: nil, ascent: 800, descent: -200)
      end.to raise_error(ArgumentError,
                         /units_per_em must be a positive Integer/)
    end

    it "raises error for non-positive units_per_em" do
      expect do
        described_class.new(units_per_em: 0, ascent: 800, descent: -200)
      end.to raise_error(ArgumentError,
                         /units_per_em must be a positive Integer/)
    end

    it "raises error for non-integer ascent" do
      expect do
        described_class.new(units_per_em: 1000, ascent: "800", descent: -200)
      end.to raise_error(ArgumentError, /ascent must be an Integer/)
    end

    it "raises error for non-integer descent" do
      expect do
        described_class.new(units_per_em: 1000, ascent: 800, descent: "-200")
      end.to raise_error(ArgumentError, /descent must be an Integer/)
    end
  end

  describe "#transform_y" do
    let(:calculator) do
      described_class.new(units_per_em: 1000, ascent: 800, descent: -200)
    end

    it "transforms Y coordinate from font space to SVG space" do
      # Font Y=0 (baseline) should map to SVG Y=800 (ascent - 0)
      expect(calculator.transform_y(0)).to eq(800)
    end

    it "transforms positive Y coordinate" do
      # Font Y=700 should map to SVG Y=100 (ascent - 700 = 800 - 700)
      expect(calculator.transform_y(700)).to eq(100)
    end

    it "transforms Y at ascent" do
      # Font Y=800 (ascent) should map to SVG Y=0 (top)
      expect(calculator.transform_y(800)).to eq(0)
    end

    it "transforms negative Y coordinate" do
      # Font Y=-200 (descent) should map to SVG Y=1000 (ascent - descent)
      expect(calculator.transform_y(-200)).to eq(1000)
    end
  end

  describe "#transform_point" do
    let(:calculator) do
      described_class.new(units_per_em: 1000, ascent: 800, descent: -200)
    end

    it "transforms point coordinates" do
      result = calculator.transform_point(100, 700)
      expect(result).to eq([100, 100])
    end

    it "transforms point at origin" do
      result = calculator.transform_point(0, 0)
      expect(result).to eq([0, 800])
    end

    it "transforms point with negative coordinates" do
      result = calculator.transform_point(-50, -100)
      expect(result).to eq([-50, 900])
    end
  end

  describe "#calculate_viewbox" do
    let(:calculator) do
      described_class.new(units_per_em: 1000, ascent: 800, descent: -200)
    end

    it "calculates viewBox for glyph bounding box" do
      viewbox = calculator.calculate_viewbox(
        x_min: 100,
        y_min: 0,
        x_max: 600,
        y_max: 700,
      )

      # x_min stays 100
      # y_min transforms from 700 to 100 (ascent - y_max)
      # width = x_max - x_min = 600 - 100 = 500
      # height = transformed_y_max - transformed_y_min = 800 - 100 = 700
      expect(viewbox).to eq("100 100 500 700")
    end

    it "calculates viewBox for full glyph range" do
      viewbox = calculator.calculate_viewbox(
        x_min: 0,
        y_min: -200,
        x_max: 1000,
        y_max: 800,
      )

      expect(viewbox).to eq("0 0 1000 1000")
    end

    it "handles negative X coordinates" do
      viewbox = calculator.calculate_viewbox(
        x_min: -50,
        y_min: 0,
        x_max: 550,
        y_max: 700,
      )

      expect(viewbox).to eq("-50 100 600 700")
    end
  end

  describe "#font_viewbox" do
    it "calculates viewBox for entire font" do
      calculator = described_class.new(
        units_per_em: 1000,
        ascent: 800,
        descent: -200,
      )

      viewbox = calculator.font_viewbox
      expect(viewbox).to eq("0 0 1000 1000")
    end

    it "handles different units per em" do
      calculator = described_class.new(
        units_per_em: 2048,
        ascent: 1638,
        descent: -410,
      )

      height = 1638 - -410
      viewbox = calculator.font_viewbox
      expect(viewbox).to eq("0 0 2048 #{height}")
    end
  end

  describe "#scale_factor" do
    let(:calculator) do
      described_class.new(units_per_em: 1000, ascent: 800, descent: -200)
    end

    it "returns 1.0 for matching units" do
      expect(calculator.scale_factor(target_units: 1000)).to eq(1.0)
    end

    it "calculates scale factor for different units" do
      expect(calculator.scale_factor(target_units: 2000)).to eq(2.0)
    end

    it "calculates scale factor for smaller units" do
      expect(calculator.scale_factor(target_units: 500)).to eq(0.5)
    end

    it "uses default target units of 1000" do
      calculator = described_class.new(
        units_per_em: 2048,
        ascent: 1638,
        descent: -410,
      )

      expect(calculator.scale_factor).to be_within(0.001).of(1000.0 / 2048)
    end
  end
end
