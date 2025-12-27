# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff2::RegionMatcher do
  describe "#initialize" do
    it "initializes with regions" do
      regions = [build_region(1)]
      matcher = described_class.new(regions)

      expect(matcher.regions).to eq(regions)
    end
  end

  describe "#calculate_scalars" do
    context "with single axis, single region" do
      let(:regions) { [build_region(1, [[-0.5, 1.0, 1.0]])] }
      let(:matcher) { described_class.new(regions) }

      it "returns 1.0 at peak coordinate" do
        scalars = matcher.calculate_scalars([1.0])
        expect(scalars).to eq([1.0])
      end

      it "returns 0.5 midway between start and peak" do
        scalars = matcher.calculate_scalars([0.25])
        expect(scalars.first).to be_within(0.01).of(0.5)
      end

      it "returns 0.0 before start" do
        scalars = matcher.calculate_scalars([-1.0])
        expect(scalars).to eq([0.0])
      end

      it "returns 0.0 after end" do
        scalars = matcher.calculate_scalars([1.5])
        expect(scalars).to eq([0.0])
      end

      it "returns 1.0 at start when start equals peak" do
        regions = [build_region(1, [[0.0, 0.0, 1.0]])]
        matcher = described_class.new(regions)
        scalars = matcher.calculate_scalars([0.0])
        expect(scalars).to eq([1.0])
      end
    end

    context "with two axes, single region" do
      let(:regions) do
        [build_region(2, [[-0.5, 1.0, 1.0], [-0.3, 0.5, 1.0]])]
      end
      let(:matcher) { described_class.new(regions) }

      it "multiplies scalars from both axes" do
        # At peak for both axes
        scalars = matcher.calculate_scalars([1.0, 0.5])
        expect(scalars).to eq([1.0])
      end

      it "returns product of axis scalars" do
        # Midway on both axes
        scalars = matcher.calculate_scalars([0.25, 0.1])
        axis1_scalar = (0.25 - (-0.5)) / (1.0 - (-0.5)) # ~0.5
        axis2_scalar = (0.1 - (-0.3)) / (0.5 - (-0.3))  # ~0.5
        expect(scalars.first).to be_within(0.01).of(axis1_scalar * axis2_scalar)
      end

      it "returns 0.0 if any axis is out of range" do
        # First axis in range, second out of range
        scalars = matcher.calculate_scalars([0.5, 2.0])
        expect(scalars).to eq([0.0])
      end
    end

    context "with multiple regions" do
      let(:regions) do
        [
          build_region(1, [[-1.0, 0.0, 0.0]]),   # Region for negative coordinates
          build_region(1, [[0.0, 1.0, 1.0]])     # Region for positive coordinates
        ]
      end
      let(:matcher) { described_class.new(regions) }

      it "returns scalars for all regions" do
        scalars = matcher.calculate_scalars([0.5])

        # First region: out of range (0.5 > 0.0 end)
        expect(scalars[0]).to eq(0.0)

        # Second region: midway between start and peak
        expect(scalars[1]).to be_within(0.01).of(0.5)
      end

      it "correctly handles coordinate at region boundaries" do
        scalars = matcher.calculate_scalars([0.0])

        # First region: at peak (end of range)
        expect(scalars[0]).to eq(1.0)

        # Second region: at start (scalar = 0.0 since start < peak)
        expect(scalars[1]).to eq(0.0)
      end
    end
  end

  describe "#calculate_axis_scalar" do
    let(:matcher) { described_class.new([]) }

    it "returns 0.0 for coordinate before start" do
      axis = { start_coord: 0.0, peak_coord: 0.5, end_coord: 1.0 }
      scalar = matcher.calculate_axis_scalar(axis, -0.5)
      expect(scalar).to eq(0.0)
    end

    it "returns 0.0 for coordinate after end" do
      axis = { start_coord: 0.0, peak_coord: 0.5, end_coord: 1.0 }
      scalar = matcher.calculate_axis_scalar(axis, 1.5)
      expect(scalar).to eq(0.0)
    end

    it "returns 1.0 at peak" do
      axis = { start_coord: 0.0, peak_coord: 0.5, end_coord: 1.0 }
      scalar = matcher.calculate_axis_scalar(axis, 0.5)
      expect(scalar).to eq(1.0)
    end

    it "interpolates between start and peak" do
      axis = { start_coord: 0.0, peak_coord: 1.0, end_coord: 1.0 }
      scalar = matcher.calculate_axis_scalar(axis, 0.5)
      expect(scalar).to be_within(0.01).of(0.5)
    end

    it "interpolates between peak and end" do
      axis = { start_coord: 0.0, peak_coord: 0.5, end_coord: 1.0 }
      scalar = matcher.calculate_axis_scalar(axis, 0.75)
      # (1.0 - 0.75) / (1.0 - 0.5) = 0.5
      expect(scalar).to be_within(0.01).of(0.5)
    end

    it "handles zero range gracefully" do
      axis = { start_coord: 0.5, peak_coord: 0.5, end_coord: 0.5 }
      scalar = matcher.calculate_axis_scalar(axis, 0.5)
      expect(scalar).to eq(1.0)
    end
  end

  describe "#coordinates_active?" do
    let(:regions) do
      [build_region(1, [[0.0, 1.0, 1.0]])]
    end
    let(:matcher) { described_class.new(regions) }

    it "returns true when coordinates activate a region" do
      expect(matcher.coordinates_active?([0.5])).to be true
    end

    it "returns false when coordinates don't activate any region" do
      expect(matcher.coordinates_active?([-1.0])).to be false
    end
  end

  describe "#active_regions" do
    let(:regions) do
      [
        build_region(1, [[-1.0, 0.0, 0.0]]),
        build_region(1, [[0.0, 1.0, 1.0]])
      ]
    end
    let(:matcher) { described_class.new(regions) }

    it "returns indices of active regions" do
      active = matcher.active_regions([0.5])
      expect(active).to eq([1])  # Only second region is active
    end

    it "returns index for region at peak" do
      active = matcher.active_regions([0.0])
      expect(active).to eq([0])  # Only first region is active (at peak)
    end

    it "returns empty array when no regions active" do
      active = matcher.active_regions([2.0])
      expect(active).to eq([])
    end
  end

  describe "#scalar_for_region" do
    let(:regions) do
      [build_region(1, [[0.0, 1.0, 1.0]])]
    end
    let(:matcher) { described_class.new(regions) }

    it "returns scalar for valid region index" do
      scalar = matcher.scalar_for_region(0, [0.5])
      expect(scalar).to be_within(0.01).of(0.5)
    end

    it "returns nil for invalid region index" do
      scalar = matcher.scalar_for_region(10, [0.5])
      expect(scalar).to be_nil
    end
  end

  describe "#validate" do
    it "returns empty array for valid regions" do
      regions = [build_region(2, [[0.0, 0.5, 1.0], [0.0, 0.5, 1.0]])]
      matcher = described_class.new(regions)
      errors = matcher.validate

      expect(errors).to be_empty
    end

    it "detects invalid coordinate ordering" do
      regions = [{
        axis_count: 1,
        axes: [{ start_coord: 1.0, peak_coord: 0.5, end_coord: 0.0 }]
      }]
      matcher = described_class.new(regions)
      errors = matcher.validate

      expect(errors).not_to be_empty
      expect(errors.first).to include("invalid ordering")
    end

    it "detects missing required keys" do
      regions = [{
        axis_count: 1,
        axes: [{ start_coord: 0.0 }]  # Missing peak_coord and end_coord
      }]
      matcher = described_class.new(regions)
      errors = matcher.validate

      expect(errors).not_to be_empty
    end

    it "detects invalid axes structure" do
      regions = [{
        axis_count: 1,
        axes: "not an array"
      }]
      matcher = described_class.new(regions)
      errors = matcher.validate

      expect(errors).not_to be_empty
      expect(errors.first).to include("invalid axes")
    end
  end

  describe "#axis_count" do
    it "returns number of axes from first region" do
      regions = [build_region(3)]
      matcher = described_class.new(regions)

      expect(matcher.axis_count).to eq(3)
    end

    it "returns 0 for empty regions" do
      matcher = described_class.new([])
      expect(matcher.axis_count).to eq(0)
    end
  end

  describe "#has_regions?" do
    it "returns true when regions present" do
      matcher = described_class.new([build_region(1)])
      expect(matcher.has_regions?).to be true
    end

    it "returns false when no regions" do
      matcher = described_class.new([])
      expect(matcher.has_regions?).to be false
    end
  end

  # Helper methods

  def build_region(num_axes, axis_coords = nil)
    axes = if axis_coords
             axis_coords.map do |coords|
               {
                 start_coord: coords[0],
                 peak_coord: coords[1],
                 end_coord: coords[2]
               }
             end
           else
             Array.new(num_axes) do
               { start_coord: 0.0, peak_coord: 1.0, end_coord: 1.0 }
             end
           end

    {
      axis_count: num_axes,
      axes: axes
    }
  end
end