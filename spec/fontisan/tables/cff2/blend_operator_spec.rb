# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff2/blend_operator"

RSpec.describe Fontisan::Tables::Cff2::BlendOperator do
  describe "#initialize" do
    it "creates a blend operator with specified axes" do
      blend = described_class.new(num_axes: 2)
      expect(blend.num_axes).to eq(2)
    end
  end

  describe "#parse" do
    let(:blend) { described_class.new(num_axes: 2) }

    it "parses blend operands correctly" do
      # Format: base1 delta1_axis1 delta1_axis2 base2 delta2_axis1 delta2_axis2 K N
      operands = [100, 10, 5, 200, 20, 10, 2, 2]

      result = blend.parse(operands)

      expect(result).not_to be_nil
      expect(result[:num_values]).to eq(2)
      expect(result[:num_axes]).to eq(2)
      expect(result[:blends].size).to eq(2)
      expect(result[:blends][0][:base]).to eq(100)
      expect(result[:blends][0][:deltas]).to eq([10, 5])
      expect(result[:blends][1][:base]).to eq(200)
      expect(result[:blends][1][:deltas]).to eq([20, 10])
    end

    it "returns nil for invalid operands" do
      # Not enough operands
      operands = [100, 2, 2]
      expect(blend.parse(operands)).to be_nil
    end

    it "handles single value blend" do
      operands = [100, 10, 5, 1, 2]

      result = blend.parse(operands)

      expect(result[:num_values]).to eq(1)
      expect(result[:blends].size).to eq(1)
    end
  end

  describe "#apply" do
    let(:blend) { described_class.new(num_axes: 2) }

    it "applies blend with scalars" do
      blend_data = {
        num_values: 2,
        num_axes: 2,
        blends: [
          { base: 100, deltas: [10, 5] },
          { base: 200, deltas: [20, 10] },
        ],
      }
      scalars = [0.5, 0.3]

      result = blend.apply(blend_data, scalars)

      # base + (delta[0] * scalar[0]) + (delta[1] * scalar[1])
      # 100 + (10 * 0.5) + (5 * 0.3) = 106.5
      # 200 + (20 * 0.5) + (10 * 0.3) = 213.0
      expect(result[0]).to be_within(0.01).of(106.5)
      expect(result[1]).to be_within(0.01).of(213.0)
    end

    it "handles zero scalars" do
      blend_data = {
        num_values: 1,
        num_axes: 2,
        blends: [
          { base: 100, deltas: [10, 5] },
        ],
      }
      scalars = [0.0, 0.0]

      result = blend.apply(blend_data, scalars)

      expect(result[0]).to eq(100.0) # No delta applied
    end

    it "handles full scalars" do
      blend_data = {
        num_values: 1,
        num_axes: 2,
        blends: [
          { base: 100, deltas: [10, 20] },
        ],
      }
      scalars = [1.0, 1.0]

      result = blend.apply(blend_data, scalars)

      expect(result[0]).to eq(130.0) # 100 + 10 + 20
    end
  end

  describe "#apply_single_blend" do
    let(:blend) { described_class.new(num_axes: 2) }

    it "applies blend to a single value" do
      blend_entry = { base: 100, deltas: [10, 20] }
      scalars = [0.5, 0.8]

      result = blend.apply_single_blend(blend_entry, scalars)

      # 100 + (10 * 0.5) + (20 * 0.8) = 121.0
      expect(result).to be_within(0.01).of(121.0)
    end
  end

  describe "#normalize_coordinate" do
    let(:blend) { described_class.new(num_axes: 1) }
    let(:axis) do
      double(
        "VariationAxisRecord",
        min_value: 400.0,
        default_value: 600.0,
        max_value: 900.0
      )
    end

    it "normalizes value below default to negative" do
      result = blend.normalize_coordinate(500.0, axis)
      # (500 - 600) / (600 - 400) = -0.5
      expect(result).to be_within(0.01).of(-0.5)
    end

    it "normalizes value above default to positive" do
      result = blend.normalize_coordinate(750.0, axis)
      # (750 - 600) / (900 - 600) = 0.5
      expect(result).to be_within(0.01).of(0.5)
    end

    it "normalizes default value to zero" do
      result = blend.normalize_coordinate(600.0, axis)
      expect(result).to eq(0.0)
    end

    it "clamps values outside range" do
      result = blend.normalize_coordinate(1000.0, axis)
      expect(result).to eq(1.0)

      result = blend.normalize_coordinate(300.0, axis)
      expect(result).to eq(-1.0)
    end
  end

  describe "#valid?" do
    let(:blend) { described_class.new(num_axes: 2) }

    it "validates correct blend data" do
      blend_data = {
        num_values: 1,
        num_axes: 2,
        blends: [
          { base: 100, deltas: [10, 5] },
        ],
      }

      expect(blend.valid?(blend_data)).to be true
    end

    it "rejects invalid structure" do
      expect(blend.valid?(nil)).to be false
      expect(blend.valid?({})).to be false
      expect(blend.valid?([])).to be false
    end

    it "rejects mismatched delta counts" do
      blend_data = {
        num_values: 1,
        num_axes: 2,
        blends: [
          { base: 100, deltas: [10] }, # Only 1 delta, should be 2
        ],
      }

      expect(blend.valid?(blend_data)).to be false
    end
  end

  describe ".operand_count" do
    it "calculates correct operand count" do
      # K=2, N=2: 2 * (2 + 1) + 2 = 8
      expect(described_class.operand_count(2, 2)).to eq(8)

      # K=1, N=3: 1 * (3 + 1) + 2 = 6
      expect(described_class.operand_count(1, 3)).to eq(6)
    end
  end

  describe ".sufficient_operands?" do
    it "checks if enough operands are available" do
      expect(described_class.sufficient_operands?(8, 2, 2)).to be true
      expect(described_class.sufficient_operands?(7, 2, 2)).to be false
      expect(described_class.sufficient_operands?(10, 2, 2)).to be true
    end
  end
end
