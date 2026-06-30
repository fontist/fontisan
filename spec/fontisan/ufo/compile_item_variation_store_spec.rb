# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::ItemVariationStore do
  describe ".build" do
    it "emits format = 1" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 1, deltas: [[10]],
      )
      format = bytes.unpack1("n")
      expect(format).to eq(1)
    end

    it "emits a single ItemVariationData block (count = 1)" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 1, deltas: [[10]],
      )
      data_count = bytes.unpack1("@6 n")
      expect(data_count).to eq(1)
    end

    it "writes variationRegionListOffset pointing at byte 12" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 1, deltas: [[10]],
      )
      region_list_offset = bytes.unpack1("@2 N")
      expect(region_list_offset).to eq(12)
    end

    it "writes itemVariationDataOffset pointing past the region list" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 1, deltas: [[10]],
      )
      region_list_offset = bytes.unpack1("@2 N")
      data_offset = bytes.unpack1("@8 N")
      expect(data_offset).to eq(region_list_offset + region_list_bytesize_for(1, 1))
    end

    it "emits a VariationRegionList with one region per master" do
      bytes = described_class.build(
        axis_count: 2, master_count: 2, item_count: 1, deltas: [[10, 5]],
      )
      region_list_offset = bytes.unpack1("@2 N")
      axis_count = bytes.unpack1("@#{region_list_offset} n")
      region_count = bytes.unpack1("@#{region_list_offset + 2} n")
      expect(axis_count).to eq(2)
      expect(region_count).to eq(2)
    end

    it "encodes a region's peak on its master's axis as 1.0 (0x4000)" do
      bytes = described_class.build(
        axis_count: 2, master_count: 2, item_count: 1, deltas: [[10, 5]],
      )
      region_list_offset = bytes.unpack1("@2 N")
      # Region 0 (master 0): axis 0 peak = 1.0, axis 1 peak = 0.0.
      # Layout per axis: start(2) + peak(2) + end(2). Region starts at +4.
      a0_peak = bytes.unpack1("@#{region_list_offset + 4 + 2} n")
      a1_peak = bytes.unpack1("@#{region_list_offset + 4 + 8} n")
      expect(to_signed(a0_peak)).to eq(0x4000) # 1.0 in f2dot14
      expect(to_signed(a1_peak)).to eq(0)      # 0.0
    end

    it "uses int8 deltas when all deltas fit in [-127, 127]" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 2,
        deltas: [[10], [50]]
      )
      data_offset = bytes.unpack1("@8 N")
      short_count = bytes.unpack1("@#{data_offset + 2} n")
      expect(short_count).to eq(0)
    end

    it "uses int16 deltas when any delta exceeds int8 range" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 2,
        deltas: [[200], [50]]
      )
      data_offset = bytes.unpack1("@8 N")
      short_count = bytes.unpack1("@#{data_offset + 2} n")
      expect(short_count).to eq(1)
    end

    it "serializes the actual delta values for each item" do
      bytes = described_class.build(
        axis_count: 1, master_count: 1, item_count: 3,
        deltas: [[10], [-20], [50]]
      )
      data_offset = bytes.unpack1("@8 N")
      # data header (6) + regionIndices (2) = 8 bytes, then 3 int8 deltas
      deltas = bytes[data_offset + 8, 3].unpack("c3")
      expect(deltas).to eq([10, -20, 50])
    end
  end

  def to_signed(uint16)
    uint16 >= 0x8000 ? uint16 - 0x10000 : uint16
  end

  def region_list_bytesize_for(axis_count, region_count)
    4 + (region_count * axis_count * 3 * 2)
  end
end
