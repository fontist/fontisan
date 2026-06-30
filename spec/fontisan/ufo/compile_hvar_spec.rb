# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Hvar do
  describe ".build" do
    it "emits version 1.0" do
      bytes = described_class.build(
        default_widths: [500], master_widths: [[600]], axis_count: 1,
      )
      version = bytes.unpack1("N")
      expect(version).to eq(0x00010000)
    end

    it "emits itemVariationStoreOffset at byte 20" do
      bytes = described_class.build(
        default_widths: [500], master_widths: [[600]], axis_count: 1,
      )
      store_offset = bytes.unpack1("@4 N")
      # HVAR header = version(4) + itemVariationStoreOffset(4) +
      # advanceWidthMappingOffset(4) + lsbMappingOffset(4) + rsbMappingOffset(4) = 20
      expect(store_offset).to eq(20)
    end

    it "leaves advance/lsb/rsb mapping offsets as 0 (implicit identity)" do
      bytes = described_class.build(
        default_widths: [500], master_widths: [[600]], axis_count: 1,
      )
      adv = bytes.unpack1("@8 N")
      lsb = bytes.unpack1("@12 N")
      rsb = bytes.unpack1("@16 N")
      expect(adv).to eq(0)
      expect(lsb).to eq(0)
      expect(rsb).to eq(0)
    end

    it "passes the ItemVariationStore through" do
      bytes = described_class.build(
        default_widths: [500, 600], master_widths: [[550, 700]], axis_count: 1,
      )
      store_offset = bytes.unpack1("@4 N")
      # ItemVariationStore format = 1 (uint16) at the start of the store block.
      format = bytes.unpack1("@#{store_offset} n")
      expect(format).to eq(1)
    end

    it "computes deltas as master_width - default_width" do
      bytes = described_class.build(
        default_widths: [500, 600],
        master_widths: [[550, 700]],
        axis_count: 1,
      )
      store_offset = bytes.unpack1("@4 N")
      data_offset_rel = bytes.unpack1("@#{store_offset + 8} N")
      data_offset = store_offset + data_offset_rel

      # ItemVariationData: itemCount(2) + shortDeltaCount(2) + regionIndexCount(2)
      # + regionIndices(2 × region_count) + delta sets.
      # 2 glyphs × 1 region, deltas 50 and 100 → both fit in int8.
      item_count = bytes.unpack1("@#{data_offset} n")
      short_count = bytes.unpack1("@#{data_offset + 2} n")
      region_index_count = bytes.unpack1("@#{data_offset + 4} n")
      expect(item_count).to eq(2)
      expect(short_count).to eq(0)
      expect(region_index_count).to eq(1)

      # Data header (6) + regionIndices (2) = 8 bytes, then 2 int8 deltas
      deltas = bytes[data_offset + 8, 2].unpack("c2")
      expect(deltas).to eq([50, 100])
    end
  end
end
