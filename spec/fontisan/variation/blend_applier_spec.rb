# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/blend_applier"
require "fontisan/variation/interpolator"

RSpec.describe Fontisan::Variation::BlendApplier do
  let(:axes) do
    [
      double("Axis", axis_tag: "wght", min_value: 400.0, default_value: 400.0, max_value: 900.0),
      double("Axis", axis_tag: "wdth", min_value: 75.0, default_value: 100.0, max_value: 125.0)
    ]
  end
  let(:interpolator) { Fontisan::Variation::Interpolator.new(axes) }

  subject(:applier) { described_class.new(interpolator) }

  describe "#initialize" do
    it "initializes with interpolator" do
      expect(applier.interpolator).to eq(interpolator)
      expect(applier.scalars).to eq([])
    end

    it "accepts initial coordinates" do
      applier_with_coords = described_class.new(interpolator, { "wght" => 700.0 })
      expect(applier_with_coords.interpolator).to eq(interpolator)
    end
  end

  describe "#set_coordinates" do
    it "calculates scalars from coordinates" do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)

      # wght: 700 is 60% from default (400) to max (900)
      # 300 / 500 = 0.6
      expect(applier.scalars[0]).to be_within(0.01).of(0.6)

      # wdth: 100 is at default
      expect(applier.scalars[1]).to eq(0.0)
    end

    it "handles coordinates at default" do
      applier.set_coordinates({ "wght" => 400.0, "wdth" => 100.0 }, axes)

      expect(applier.scalars[0]).to eq(0.0)
      expect(applier.scalars[1]).to eq(0.0)
    end

    it "handles coordinates at extremes" do
      applier.set_coordinates({ "wght" => 900.0, "wdth" => 125.0 }, axes)

      expect(applier.scalars[0]).to eq(1.0)
      expect(applier.scalars[1]).to eq(1.0)
    end
  end

  describe "#apply_blend" do
    before do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 110.0 }, axes)
    end

    it "applies single delta with scalar" do
      # wght scalar = 0.6, wdth scalar = 0.4
      result = applier.apply_blend(base: 100, deltas: [10, 5])

      # 100 + (10 * 0.6) + (5 * 0.4) = 100 + 6 + 2 = 108
      expect(result).to be_within(0.01).of(108.0)
    end

    it "returns base value when at default" do
      applier.set_coordinates({ "wght" => 400.0, "wdth" => 100.0 }, axes)
      result = applier.apply_blend(base: 100, deltas: [10, 5])

      expect(result).to eq(100.0)
    end

    it "applies maximum delta at extreme" do
      applier.set_coordinates({ "wght" => 900.0, "wdth" => 100.0 }, axes)
      result = applier.apply_blend(base: 100, deltas: [50, 0])

      # 100 + (50 * 1.0) + (0 * 0.0) = 150
      expect(result).to eq(150.0)
    end

    it "handles negative deltas" do
      result = applier.apply_blend(base: 100, deltas: [-10, -5])

      # wght scalar ≈ 0.6, wdth scalar ≈ 0.4
      # 100 + (-10 * 0.6) + (-5 * 0.4) = 100 - 6 - 2 = 92
      expect(result).to be_within(0.01).of(92.0)
    end

    it "handles zero deltas" do
      result = applier.apply_blend(base: 100, deltas: [0, 0])
      expect(result).to eq(100.0)
    end

    it "warns on delta count mismatch" do
      expect do
        applier.apply_blend(base: 100, deltas: [10], num_axes: 2)
      end.to raise_error(Fontisan::InvalidVariationDataError, /doesn't match axes/)
    end

    it "returns base on delta count mismatch" do
      expect do
        applier.apply_blend(base: 100, deltas: [10], num_axes: 2)
      end.to raise_error(Fontisan::InvalidVariationDataError)
    end
  end

  describe "#apply_blends" do
    before do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)
    end

    it "applies multiple blend operations" do
      blends = [
        { base: 100, deltas: [10, 0] },
        { base: 200, deltas: [20, 0] },
        { base: 50, deltas: [5, 0] }
      ]

      results = applier.apply_blends(blends, 2)

      # wght scalar = 0.6
      expect(results[0]).to be_within(0.01).of(106.0)  # 100 + 10*0.6
      expect(results[1]).to be_within(0.01).of(212.0)  # 200 + 20*0.6
      expect(results[2]).to be_within(0.01).of(53.0)   # 50 + 5*0.6
    end

    it "handles empty blend array" do
      results = applier.apply_blends([], 2)
      expect(results).to eq([])
    end
  end

  describe "#apply_blend_operands" do
    before do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)
    end

    it "applies blend from CharString operands" do
      # Format: v1 Δv1_1 Δv1_2 v2 Δv2_1 Δv2_2 K N
      # K=2 values, N=2 axes
      operands = [100, 10, 5, 200, 20, 10]

      results = applier.apply_blend_operands(operands, 2, 2)

      # wght scalar ≈ 0.6, wdth scalar = 0.0
      expect(results[0]).to be_within(0.01).of(106.0)  # 100 + 10*0.6 + 5*0.0
      expect(results[1]).to be_within(0.01).of(212.0)  # 200 + 20*0.6 + 10*0.0
    end

    it "handles single value blend" do
      # K=1 value, N=2 axes
      operands = [100, 10, 5]

      results = applier.apply_blend_operands(operands, 1, 2)

      expect(results.length).to eq(1)
      expect(results[0]).to be_within(0.01).of(106.0)
    end

    it "handles operand count mismatch" do
      # Expected 6 operands (2 * (2 + 1)), given 5
      operands = [100, 10, 5, 200, 20]

      expect do
        applier.apply_blend_operands(operands, 2, 2)
      end.to raise_error(Fontisan::InvalidVariationDataError, /operand count mismatch/)
    end
  end

  describe "#at_default?" do
    it "returns true when all scalars are zero" do
      applier.set_coordinates({ "wght" => 400.0, "wdth" => 100.0 }, axes)
      expect(applier.at_default?).to be true
    end

    it "returns false when any scalar is non-zero" do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)
      expect(applier.at_default?).to be false
    end

    it "returns true for empty scalars" do
      expect(applier.at_default?).to be true
    end
  end

  describe "#blend_point" do
    before do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 110.0 }, axes)
    end

    it "blends X and Y coordinates together" do
      x, y = applier.blend_point(100, 200, [10, 5], [20, 10])

      # wght ≈ 0.6, wdth ≈ 0.4
      # x: 100 + 10*0.6 + 5*0.4 = 108
      # y: 200 + 20*0.6 + 10*0.4 = 216
      expect(x).to be_within(0.01).of(108.0)
      expect(y).to be_within(0.01).of(216.0)
    end

    it "returns base coordinates at default" do
      applier.set_coordinates({ "wght" => 400.0, "wdth" => 100.0 }, axes)
      x, y = applier.blend_point(100, 200, [10, 5], [20, 10])

      expect(x).to eq(100.0)
      expect(y).to eq(200.0)
    end
  end

  describe "#blend_to_static" do
    before do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)
    end

    it "converts blend data to static values" do
      blend_data = [
        {
          num_axes: 2,
          blends: [
            { base: 100, deltas: [10, 0] },
            { base: 200, deltas: [20, 0] }
          ]
        }
      ]

      results = applier.blend_to_static(blend_data)

      expect(results.length).to eq(2)
      expect(results[0]).to be_within(0.01).of(106.0)
      expect(results[1]).to be_within(0.01).of(212.0)
    end

    it "handles multiple blend operations" do
      blend_data = [
        {
          num_axes: 2,
          blends: [{ base: 100, deltas: [10, 0] }]
        },
        {
          num_axes: 2,
          blends: [{ base: 200, deltas: [20, 0] }]
        }
      ]

      results = applier.blend_to_static(blend_data)

      expect(results.length).to eq(2)
      expect(results[0]).to be_within(0.01).of(106.0)
      expect(results[1]).to be_within(0.01).of(212.0)
    end

    it "returns empty array for empty blend data" do
      results = applier.blend_to_static([])
      expect(results).to eq([])
    end
  end

  describe "integration scenarios" do
    it "handles complete CharString blend workflow" do
      # Set coordinates
      applier.set_coordinates({ "wght" => 650.0, "wdth" => 112.5 }, axes)

      # wght: (650-400)/(900-400) = 250/500 = 0.5
      # wdth: (112.5-100)/(125-100) = 12.5/25 = 0.5

      # Apply blend for a control point
      x_base, y_base = 100.0, 200.0
      x_deltas, y_deltas = [20, 10], [40, 20]

      x, y = applier.blend_point(x_base, y_base, x_deltas, y_deltas)

      # x: 100 + 20*0.5 + 10*0.5 = 100 + 10 + 5 = 115
      # y: 200 + 40*0.5 + 20*0.5 = 200 + 20 + 10 = 230
      expect(x).to be_within(0.01).of(115.0)
      expect(y).to be_within(0.01).of(230.0)
    end

    it "maintains precision across multiple blend operations" do
      applier.set_coordinates({ "wght" => 700.0, "wdth" => 100.0 }, axes)

      # Apply multiple sequential blends
      results = []
      10.times do |i|
        result = applier.apply_blend(base: i * 100, deltas: [i * 10, 0])
        results << result
      end

      # Verify precision maintained
      expect(results[5]).to be_within(0.01).of(530.0)  # 500 + 50*0.6
      expect(results[9]).to be_within(0.01).of(954.0)  # 900 + 90*0.6
    end
  end
end
