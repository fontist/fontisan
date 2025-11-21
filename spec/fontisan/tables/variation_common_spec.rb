# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::VariationCommon do
  describe Fontisan::Tables::VariationCommon::RegionAxisCoordinates do
    def build_region_axis_coordinates(start: 0.0, peak: 1.0, end_val: 1.0)
      data = (+"").b
      # F2DOT14 format: multiply by 16384
      data << [(start * 16384).to_i].pack("s>")
      data << [(peak * 16384).to_i].pack("s>")
      data << [(end_val * 16384).to_i].pack("s>")
      data
    end

    it "parses start coordinate" do
      data = build_region_axis_coordinates(start: 0.5)
      coords = described_class.read(data)
      expect(coords.start).to be_within(0.001).of(0.5)
    end

    it "parses peak coordinate" do
      data = build_region_axis_coordinates(peak: 1.0)
      coords = described_class.read(data)
      expect(coords.peak).to be_within(0.001).of(1.0)
    end

    it "parses end coordinate" do
      data = build_region_axis_coordinates(end_val: 0.75)
      coords = described_class.read(data)
      expect(coords.end_value).to be_within(0.001).of(0.75)
    end

    it "handles negative values" do
      data = build_region_axis_coordinates(start: -1.0, peak: -0.5,
                                           end_val: 0.0)
      coords = described_class.read(data)
      expect(coords.start).to be_within(0.001).of(-1.0)
      expect(coords.peak).to be_within(0.001).of(-0.5)
      expect(coords.end_value).to be_within(0.001).of(0.0)
    end
  end

  describe Fontisan::Tables::VariationCommon::VariationRegion do
    it "parses coordinates for multiple axes" do
      axis_count = 2
      data = (+"").b
      # Axis 1: 0.0, 0.5, 1.0
      data << [(0.0 * 16384).to_i].pack("s>")
      data << [(0.5 * 16384).to_i].pack("s>")
      data << [(1.0 * 16384).to_i].pack("s>")
      # Axis 2: -1.0, 0.0, 1.0
      data << [(-1.0 * 16384).to_i].pack("s>")
      data << [(0.0 * 16384).to_i].pack("s>")
      data << [(1.0 * 16384).to_i].pack("s>")

      coords = described_class.parse_coordinates(data, axis_count)
      expect(coords.length).to eq(2)
      expect(coords[0].peak).to be_within(0.001).of(0.5)
      expect(coords[1].peak).to be_within(0.001).of(0.0)
    end
  end

  describe Fontisan::Tables::VariationCommon::VariationRegionList do
    def build_region_list(axis_count: 2, region_count: 1)
      data = (+"").b
      data << [axis_count].pack("n")
      data << [region_count].pack("n")

      # Add region data
      region_count.times do
        axis_count.times do
          # Start, peak, end for each axis (F2DOT14)
          data << [0].pack("s>") # start
          data << [(1.0 * 16384).to_i].pack("s>") # peak
          data << [(1.0 * 16384).to_i].pack("s>") # end
        end
      end
      data
    end

    it "parses axis count" do
      data = build_region_list(axis_count: 3)
      region_list = described_class.read(data)
      expect(region_list.axis_count).to eq(3)
    end

    it "parses region count" do
      data = build_region_list(region_count: 2)
      region_list = described_class.read(data)
      expect(region_list.region_count).to eq(2)
    end

    it "parses regions" do
      data = build_region_list(axis_count: 2, region_count: 2)
      region_list = described_class.read(data)
      regions = region_list.regions
      expect(regions.length).to eq(2)
      expect(regions[0].length).to eq(2) # 2 axes
    end
  end

  describe Fontisan::Tables::VariationCommon::ItemVariationData do
    def build_item_variation_data(
      item_count: 1,
      short_delta_count: 1,
      region_index_count: 1
    )
      data = (+"").b
      data << [item_count].pack("n")
      data << [short_delta_count].pack("n")
      data << [region_index_count].pack("n")

      # Region indices
      region_index_count.times do |i|
        data << [i].pack("n")
      end

      # Delta data for each item
      item_count.times do
        # Short deltas (int16)
        short_delta_count.times do
          data << [10].pack("s>")
        end
        # Long deltas (int8)
        long_count = region_index_count - short_delta_count
        long_count.times do
          data << [5].pack("c")
        end
      end
      data
    end

    it "parses item count" do
      data = build_item_variation_data(item_count: 5)
      item_data = described_class.read(data)
      expect(item_data.item_count).to eq(5)
    end

    it "parses short delta count" do
      data = build_item_variation_data(short_delta_count: 2)
      item_data = described_class.read(data)
      expect(item_data.short_delta_count).to eq(2)
    end

    it "parses region indices" do
      data = build_item_variation_data(region_index_count: 3)
      item_data = described_class.read(data)
      indices = item_data.region_indices
      expect(indices).to eq([0, 1, 2])
    end

    it "parses delta sets" do
      data = build_item_variation_data(
        item_count: 2,
        short_delta_count: 1,
        region_index_count: 2,
      )
      item_data = described_class.read(data)
      delta_sets = item_data.delta_sets
      expect(delta_sets.length).to eq(2)
      expect(delta_sets[0]).to eq([10, 5])
    end
  end

  describe Fontisan::Tables::VariationCommon::ItemVariationStore do
    def build_item_variation_store
      data = (+"").b
      data << [1].pack("n") # format
      data << [16].pack("N") # region list offset
      data << [1].pack("n") # data count
      data << [26].pack("N") # data offset

      # Add padding to reach offset 16 (currently at offset 12)
      data << "\x00\x00\x00\x00"

      # Region list at offset 16
      data << [1].pack("n") # axis count
      data << [1].pack("n") # region count
      # Region data (1 axis)
      data << [0].pack("s>") # start
      data << [(1.0 * 16384).to_i].pack("s>") # peak
      data << [(1.0 * 16384).to_i].pack("s>") # end
      # Region list ends at offset 26

      # Item variation data at offset 26
      data << [1].pack("n") # item count
      data << [1].pack("n") # short delta count
      data << [1].pack("n") # region index count
      data << [0].pack("n") # region index
      data << [10].pack("s>") # delta value

      data
    end

    it "parses format" do
      data = build_item_variation_store
      store = described_class.read(data)
      expect(store.format).to eq(1)
    end

    it "parses variation region list" do
      data = build_item_variation_store
      store = described_class.read(data)
      region_list = store.variation_region_list
      expect(region_list).not_to be_nil
      expect(region_list.axis_count).to eq(1)
    end

    it "parses item variation data entries" do
      data = build_item_variation_store
      store = described_class.read(data)
      entries = store.item_variation_data_entries
      expect(entries.length).to eq(1)
      expect(entries[0].item_count).to eq(1)
    end

    it "retrieves delta set by indices" do
      data = build_item_variation_store
      store = described_class.read(data)
      delta_set = store.delta_set(0, 0)
      expect(delta_set).to eq([10])
    end
  end

  describe Fontisan::Tables::VariationCommon::DeltaSetIndexMap do
    def build_delta_set_index_map_format0(map_count: 3)
      data = (+"").b
      data << [0].pack("C") # format
      data << [0x00].pack("C") # entry format (1+1 bytes per entry)
      data << [map_count].pack("n") # map count

      # Map data - each entry has outer (1 byte) and inner (1 byte) indices
      map_count.times do |i|
        data << [i >> 8].pack("C") # outer index (high byte)
        data << [i & 0xFF].pack("C") # inner index (low byte)
      end
      data
    end

    it "parses format" do
      data = build_delta_set_index_map_format0
      map = described_class.read(data)
      expect(map.format).to eq(0)
    end

    it "parses entry format" do
      data = build_delta_set_index_map_format0
      map = described_class.read(data)
      expect(map.entry_format).to eq(0x00)
    end

    it "parses map data" do
      data = build_delta_set_index_map_format0(map_count: 5)
      map = described_class.read(data)
      map_data = map.map_data
      expect(map_data).to eq([0, 1, 2, 3, 4])
    end
  end
end
