# frozen_string_literal: true

require "spec_helper"
require "fontisan"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Fvar do
  describe ".build" do
    it "returns nil when no axes are defined" do
      font = Fontisan::Ufo::Font.new
      expect(described_class.build(font)).to be_nil
    end

    it "returns nil when axes list is empty" do
      font = Fontisan::Ufo::Font.new
      expect(described_class.build(font, axes: [])).to be_nil
    end

    it "builds a valid fvar header for a single axis" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [{ tag: "wght", min: 100, default: 400, max: 900 }],
      )

      major, minor = bytes.unpack("@0 n n")
      expect(major).to eq(1)
      expect(minor).to eq(0)
    end

    it "encodes axis min/default/max as Fixed 16.16" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [{ tag: "wght", min: 100, default: 400, max: 900 }],
      )

      # After 16 bytes of header, the axis record starts.
      # axisTag (4) + minValue (4) + defaultValue (4) + maxValue (4) ...
      axis_data = bytes[16, 20]
      tag = axis_data[0, 4]
      min, default, max = axis_data[4, 12].unpack("N*")

      expect(tag).to eq("wght")
      expect(min).to eq(100 * 65_536)      # 100.0 in Fixed
      expect(default).to eq(400 * 65_536)  # 400.0
      expect(max).to eq(900 * 65_536)      # 900.0
    end

    it "emits multiple axes" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [
          { tag: "wght", min: 100, default: 400, max: 900 },
          { tag: "wdth", min: 75, default: 100, max: 125 },
        ],
      )

      axis_count = bytes.unpack1("@8 n")
      expect(axis_count).to eq(2)
      expect(bytes.bytesize).to be >= (16 + 2 * 20)
    end

    it "emits named instances when provided" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [{ tag: "wght", min: 100, default: 400, max: 900 }],
        instances: [
          { name_id: 256, flags: 0, coords: [400] },
          { name_id: 257, flags: 0, coords: [700] },
        ],
      )

      instance_count = bytes.unpack1("@12 n")
      expect(instance_count).to eq(2)
    end

    it "pads instance coords to axis count" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [
          { tag: "wght", min: 100, default: 400, max: 900 },
          { tag: "wdth", min: 75, default: 100, max: 125 },
        ],
        instances: [{ name_id: 256, flags: 0, coords: [500] }], # only 1 coord for 2 axes
      )

      # header(16) + axes(2*20) + instances(1 * (4 + 2*4))
      expected_min = 16 + (2 * 20) + (4 + (2 * 4))
      expect(bytes.bytesize).to be >= expected_min
    end

    it "emits an axisSize of 20 bytes" do
      font = Fontisan::Ufo::Font.new
      bytes = described_class.build(
        font,
        axes: [{ tag: "wght", min: 100, default: 400, max: 900 }],
      )

      axis_size = bytes.unpack1("@10 n")
      expect(axis_size).to eq(20)
    end
  end
end
