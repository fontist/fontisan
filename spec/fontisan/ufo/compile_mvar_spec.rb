# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Mvar do
  describe ".build" do
    it "emits major/minor version 1.0" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      major, minor = bytes.unpack("nn")
      expect(major).to eq(1)
      expect(minor).to eq(0)
    end

    it "emits valueRecordSize = 8" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      value_record_size = bytes.unpack1("@4 n")
      expect(value_record_size).to eq(8)
    end

    it "emits valueRecordCount equal to the number of metric tags" do
      bytes = described_class.build(
        default_metrics: { hasc: 800, hdsc: -200, hlgp: 600 },
        master_metrics: [{ hasc: 900, hdsc: -250, hlgp: 650 }],
        axis_count: 1,
      )
      record_count = bytes.unpack1("@6 n")
      expect(record_count).to eq(3)
    end

    it "emits itemVariationStoreOffset = header + value records" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      store_offset = bytes.unpack1("@8 n")
      expect(store_offset).to eq(18) # 10-byte header + 1 × 8-byte record
    end

    it "writes a value record per tag with the correct tag bytes" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      # Records start right after the 10-byte header.
      tag = bytes[10, 4]
      expect(tag).to eq("hasc")
    end

    it "passes the ItemVariationStore through with format = 1" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      store_offset = bytes.unpack1("@8 n")
      format = bytes.unpack1("@#{store_offset} n")
      expect(format).to eq(1)
    end

    it "computes the delta as master_value - default_value" do
      bytes = described_class.build(
        default_metrics: { hasc: 800 },
        master_metrics: [{ hasc: 900 }],
        axis_count: 1,
      )
      store_offset = bytes.unpack1("@8 n")
      data_offset_rel = bytes.unpack1("@#{store_offset + 8} N")
      data_offset = store_offset + data_offset_rel

      # ItemVariationData: itemCount(2) + shortDeltaCount(2) + regionIndexCount(2)
      # + regionIndices(2 × 1) = 8 bytes, then 1 int8 delta
      delta = bytes.unpack1("@#{data_offset + 8} c")
      expect(delta).to eq(100) # 900 - 800
    end
  end
end
