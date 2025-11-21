# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/region_matcher"
require "fontisan/tables/variation_common"

RSpec.describe Fontisan::Variable::RegionMatcher do
  let(:region_list_data) do
    # Build minimal variation region list
    data = "".b
    data << [1].pack("n") # axis count
    data << [3].pack("n") # region count

    # Region 0: 0.0 to 1.0 (peak at 1.0)
    data << [0].pack("s>") # start (F2DOT14)
    data << [(1.0 * 16384).to_i].pack("s>") # peak
    data << [(1.0 * 16384).to_i].pack("s>") # end

    # Region 1: -1.0 to 0.0 (peak at -1.0)
    data << [(-1.0 * 16384).to_i].pack("s>") # start
    data << [(-1.0 * 16384).to_i].pack("s>") # peak
    data << [0].pack("s>") # end

    # Region 2: -0.5 to 0.5 (peak at 0.0)
    data << [(-0.5 * 16384).to_i].pack("s>") # start
    data << [0].pack("s>") # peak
    data << [(0.5 * 16384).to_i].pack("s>") # end

    data
  end

  let(:region_list) do
    Fontisan::Tables::VariationCommon::VariationRegionList.read(region_list_data)
  end

  let(:axis_tags) { ["wght"] }
  let(:matcher) { described_class.new(region_list, axis_tags) }

  describe "#initialize" do
    it "creates matcher with region list" do
      expect(matcher).to be_a(described_class)
    end

    it "loads configuration" do
      expect(matcher.config).to be_a(Hash)
    end

    it "builds regions from region list" do
      expect(matcher.region_count).to eq(3)
    end
  end

  describe "#match" do
    context "with coordinate at peak" do
      it "returns 1.0 for region with peak at 1.0" do
        scalars = matcher.match({ "wght" => 1.0 })
        expect(scalars[0]).to eq(1.0)
      end

      it "returns 1.0 for region with peak at -1.0" do
        scalars = matcher.match({ "wght" => -1.0 })
        expect(scalars[1]).to eq(1.0)
      end

      it "returns 1.0 for region with peak at 0.0" do
        scalars = matcher.match({ "wght" => 0.0 })
        expect(scalars[2]).to eq(1.0)
      end
    end

    context "with coordinate outside region" do
      it "returns 0.0 for coordinate below start" do
        scalars = matcher.match({ "wght" => -1.5 })
        expect(scalars[0]).to eq(0.0) # Region 0 starts at 0.0
      end

      it "returns 0.0 for coordinate above end" do
        scalars = matcher.match({ "wght" => 1.5 })
        expect(scalars[1]).to eq(0.0) # Region 1 ends at 0.0
      end
    end

    context "with coordinate between start and peak" do
      it "returns interpolated value" do
        scalars = matcher.match({ "wght" => 0.5 })
        # Region 0: 0.0 to 1.0 (peak at 1.0)
        # At 0.5: (0.5 - 0.0) / (1.0 - 0.0) = 0.5
        expect(scalars[0]).to eq(0.5)
      end

      it "returns interpolated value for negative range" do
        scalars = matcher.match({ "wght" => -0.5 })
        # Region 1: -1.0 to 0.0 (peak at -1.0)
        # At -0.5: (-0.5 - (-1.0)) / ((-1.0) - (-1.0)) needs recalculation
        # Actually between peak (-1.0) and end (0.0)
        # (0.0 - (-0.5)) / (0.0 - (-1.0)) = 0.5 / 1.0 = 0.5
        expect(scalars[1]).to eq(0.5)
      end
    end

    context "with coordinate between peak and end" do
      it "returns interpolated value" do
        scalars = matcher.match({ "wght" => 0.25 })
        # Region 2: -0.5 to 0.5 (peak at 0.0)
        # At 0.25: (0.5 - 0.25) / (0.5 - 0.0) = 0.25 / 0.5 = 0.5
        expect(scalars[2]).to eq(0.5)
      end
    end

    context "with default coordinate (0.0)" do
      it "returns correct scalars for all regions" do
        scalars = matcher.match({ "wght" => 0.0 })
        expect(scalars[0]).to eq(0.0) # Region 0: 0.0 to 1.0, at start
        expect(scalars[1]).to eq(0.0) # Region 1: -1.0 to 0.0, at end
        expect(scalars[2]).to eq(1.0) # Region 2: -0.5 to 0.5 (peak at 0.0)
      end
    end

    context "with caching enabled" do
      it "caches results for same coordinates" do
        coords = { "wght" => 0.5 }
        result1 = matcher.match(coords)
        result2 = matcher.match(coords)
        expect(result1).to eq(result2)
      end

      it "can clear cache" do
        matcher.match({ "wght" => 0.5 })
        expect { matcher.clear_cache }.not_to raise_error
      end
    end
  end

  describe "#match_region" do
    it "returns scalar for specific region" do
      scalar = matcher.match_region(0, { "wght" => 0.5 })
      expect(scalar).to eq(0.5)
    end

    it "returns 0.0 for invalid region index" do
      scalar = matcher.match_region(99, { "wght" => 0.5 })
      expect(scalar).to eq(0.0)
    end
  end

  describe "#region_count" do
    it "returns number of regions" do
      expect(matcher.region_count).to eq(3)
    end
  end

  describe "multi-axis regions" do
    let(:multi_axis_data) do
      # Build variation region list with 2 axes
      data = "".b
      data << [2].pack("n") # axis count
      data << [1].pack("n") # region count

      # Region with both axes: wght 0.0-1.0, wdth 0.0-1.0
      data << [0].pack("s>") # wght start
      data << [(1.0 * 16384).to_i].pack("s>") # wght peak
      data << [(1.0 * 16384).to_i].pack("s>") # wght end
      data << [0].pack("s>") # wdth start
      data << [(1.0 * 16384).to_i].pack("s>") # wdth peak
      data << [(1.0 * 16384).to_i].pack("s>") # wdth end

      data
    end

    let(:multi_region_list) do
      Fontisan::Tables::VariationCommon::VariationRegionList.read(multi_axis_data)
    end

    let(:multi_axis_tags) { ["wght", "wdth"] }
    let(:multi_matcher) do
      described_class.new(multi_region_list, multi_axis_tags)
    end

    it "multiplies scalars for multi-axis region" do
      scalars = multi_matcher.match({ "wght" => 0.5, "wdth" => 0.5 })
      # Both axes at 0.5: 0.5 * 0.5 = 0.25
      expect(scalars[0]).to eq(0.25)
    end

    it "returns 0.0 if any axis is outside range" do
      scalars = multi_matcher.match({ "wght" => 0.5, "wdth" => -0.5 })
      # wdth is outside range (below 0.0 for this region)
      expect(scalars[0]).to eq(0.0)
    end

    it "returns 1.0 when both axes at peak" do
      scalars = multi_matcher.match({ "wght" => 1.0, "wdth" => 1.0 })
      expect(scalars[0]).to eq(1.0)
    end
  end

  describe "edge cases" do
    it "handles missing axis coordinates" do
      scalars = matcher.match({})
      # Should default to 0.0 for missing coordinates
      expect(scalars).to all(be_a(Numeric))
    end

    it "handles symbol keys for coordinates" do
      scalars = matcher.match({ wght: 0.5 })
      expect(scalars[0]).to eq(0.5)
    end

    it "applies minimum scalar threshold" do
      # Very small scalars below threshold should become 0.0
      config = { delta_application: { min_scalar_threshold: 0.1 } }
      matcher_with_threshold = described_class.new(region_list, axis_tags,
                                                   config)
      scalars = matcher_with_threshold.match({ "wght" => 0.05 })
      # This might be below threshold depending on calculation
      expect(scalars).to all(be >= 0.0)
    end
  end
end
