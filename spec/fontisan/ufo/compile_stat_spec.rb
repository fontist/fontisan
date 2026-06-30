# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Stat do
  describe ".build" do
    it "returns nil when axes is nil" do
      expect(described_class.build(axes: nil)).to be_nil
    end

    it "returns nil when axes is empty" do
      expect(described_class.build(axes: [])).to be_nil
    end

    it "emits version 1.1 (0x00010001)" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
      )
      version = bytes.unpack1("N")
      expect(version).to eq(0x00010001)
    end

    it "emits designAxisSize = 8 (size of each DesignAxisRecord)" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
      )
      design_axis_size = bytes.unpack1("@4 n")
      expect(design_axis_size).to eq(8)
    end

    it "emits designAxisCount" do
      bytes = described_class.build(
        axes: [
          { tag: "wght", name_id: 256, ordering: 0 },
          { tag: "wdth", name_id: 257, ordering: 1 },
        ],
      )
      count = bytes.unpack1("@6 n")
      expect(count).to eq(2)
    end

    it "writes a design axis record with tag + nameID + ordering" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
      )
      # designAxesOffset is at byte 8 (uint32); axis record starts there.
      axes_offset = bytes.unpack1("@8 N")
      expect(axes_offset).to eq(20) # header size
      tag = bytes[axes_offset, 4]
      name_id, ordering = bytes[axes_offset + 4, 4].unpack("nn")
      expect(tag).to eq("wght")
      expect(name_id).to eq(256)
      expect(ordering).to eq(0)
    end

    it "emits axisValueCount matching the supplied axis_values" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
        axis_values: [
          { axis_index: 0, flags: 0, name_id: 258, value: 400.0 },
          { axis_index: 0, flags: 0, name_id: 259, value: 700.0 },
        ],
      )
      value_count = bytes.unpack1("@12 n")
      expect(value_count).to eq(2)
    end

    it "writes an axis value table (Format 1: nominal) per axis value" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
        axis_values: [
          { axis_index: 0, flags: 0, name_id: 258, value: 400.0 },
        ],
      )
      # The offset to the value offsets array is at byte 14 (uint32, per the spec).
      value_offsets_offset = bytes.unpack1("@14 N")
      # First offset (uint32) points at the first axis value table.
      first_table_offset = bytes.unpack1("@#{value_offsets_offset} N")
      format, axis_idx, flags, name_id = bytes[first_table_offset, 8].unpack("nnnn")
      expect(format).to eq(1)
      expect(axis_idx).to eq(0)
      expect(flags).to eq(0)
      expect(name_id).to eq(258)
    end

    it "writes the elidedNameID at the end of the header" do
      bytes = described_class.build(
        axes: [{ tag: "wght", name_id: 256, ordering: 0 }],
        elided_name_id: 2,
      )
      elided_id = bytes.unpack1("@18 n")
      expect(elided_id).to eq(2)
    end
  end
end
