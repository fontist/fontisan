# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Avar do
  describe ".build" do
    it "returns nil when axes is nil" do
      expect(described_class.build(axes: nil)).to be_nil
    end

    it "returns nil when axes is empty" do
      expect(described_class.build(axes: [])).to be_nil
    end

    it "emits version 1.0" do
      bytes = described_class.build(axes: [{ tag: "wght" }])
      version = bytes.unpack1("N")
      expect(version).to eq(0x00010000)
    end

    it "emits reserved uint16 = 0 after version" do
      bytes = described_class.build(axes: [{ tag: "wght" }])
      reserved = bytes.unpack1("@4 n")
      expect(reserved).to eq(0)
    end

    it "emits the correct axis count" do
      bytes = described_class.build(
        axes: [
          { tag: "wght" },
          { tag: "wdth" },
        ],
      )
      axis_count = bytes.unpack1("@6 n")
      expect(axis_count).to eq(2)
    end

    it "emits 3 default maps per axis when no maps are supplied" do
      bytes = described_class.build(axes: [{ tag: "wght" }])
      # After 8-byte header, each axis starts with a uint16 mapCount.
      map_count = bytes.unpack1("@8 n")
      expect(map_count).to eq(3)
    end

    it "encodes default maps -1/-1, 0/0, 1/1 as f2dot14" do
      bytes = described_class.build(axes: [{ tag: "wght" }])
      # header(8) + mapCount(2) = 10, then 3 pairs of int16.
      pairs = bytes[10, 12].unpack("n6")
      # f2dot14(-1.0) = -16384 = 0xC000 (uint16)
      # f2dot14(0.0)  = 0
      # f2dot14(1.0)  = 16384 = 0x4000
      expect(pairs[0]).to eq(0xC000) # -1.0
      expect(pairs[1]).to eq(0xC000) # -1.0
      expect(pairs[2]).to eq(0)      # 0.0
      expect(pairs[3]).to eq(0)      # 0.0
      expect(pairs[4]).to eq(0x4000) # 1.0
      expect(pairs[5]).to eq(0x4000) # 1.0
    end

    it "emits custom maps when supplied" do
      bytes = described_class.build(
        axes: [
          {
            tag: "wght",
            maps: [[-1.0, -0.5], [0.0, 0.0], [1.0, 0.8]],
          },
        ],
      )
      map_count = bytes.unpack1("@8 n")
      expect(map_count).to eq(3)

      pairs = bytes[10, 12].unpack("n6")
      # -1.0 → -16384 → 0xC000; -0.5 → -8192 → 0xE000 (as uint16)
      # 1.0 → 16384 → 0x4000; 0.8 → 13107 → 0x3333
      expect(pairs[0]).to eq(0xC000) # from -1.0
      expect(pairs[1]).to eq(0xE000) # to   -0.5
      expect(pairs[4]).to eq(0x4000) # from  1.0
      expect(pairs[5]).to eq(0x3333) # to    0.8
    end

    it "emits multiple axis segments back-to-back" do
      bytes = described_class.build(
        axes: [
          { tag: "wght" },
          { tag: "wdth" },
        ],
      )
      # header(8) + axis0 (2 + 12) = 22; axis1 mapCount starts at offset 22.
      map_count_axis1 = bytes.unpack1("@22 n")
      expect(map_count_axis1).to eq(3)
    end
  end
end
