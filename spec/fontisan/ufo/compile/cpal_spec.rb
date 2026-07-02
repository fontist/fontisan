# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile"

RSpec.describe Fontisan::Ufo::Compile::Cpal do
  describe ".build" do
    it "returns nil for nil palettes" do
      expect(described_class.build(palettes: nil)).to be_nil
    end

    it "returns nil for empty palettes" do
      expect(described_class.build(palettes: [])).to be_nil
    end

    it "produces a valid CPAL v0 header" do
      palettes = [[
        described_class::Color.new(blue: 0, green: 0, red: 255, alpha: 255),
      ]]
      bytes = described_class.build(palettes: palettes)
      version, num_entries, num_palettes, num_records, offset = bytes.unpack("nnnnN")
      expect(version).to eq(0)
      expect(num_entries).to eq(1)
      expect(num_palettes).to eq(1)
      expect(num_records).to eq(1)
      expect(offset).to eq(12 + 2) # header + 1 palette index
    end

    it "encodes color records as BGRA" do
      palettes = [[
        described_class::Color.new(blue: 10, green: 20, red: 30, alpha: 40),
      ]]
      bytes = described_class.build(palettes: palettes)
      record_offset = 12 + 2 # header + 1 index
      bgra = bytes[record_offset, 4].unpack("C4")
      expect(bgra).to eq([10, 20, 30, 40])
    end

    it "handles multiple palettes with multiple entries each" do
      red = described_class::Color.new(red: 255, alpha: 255)
      green = described_class::Color.new(green: 255, alpha: 255)
      palettes = [[red, green], [green, red]]
      bytes = described_class.build(palettes: palettes)
      _, num_entries, num_palettes, num_records, offset = bytes.unpack("nnnnN")
      expect(num_entries).to eq(2)
      expect(num_palettes).to eq(2)
      expect(num_records).to eq(4)
      expect(offset).to eq(12 + 4) # header + 2 palette indices
    end

    it "accepts hash colors as an alternative to Color structs" do
      palettes = [[{ blue: 0, green: 128, red: 255, alpha: 255 }]]
      bytes = described_class.build(palettes: palettes)
      record_offset = 14
      bgra = bytes[record_offset, 4].unpack("C4")
      expect(bgra).to eq([0, 128, 255, 255])
    end
  end
end
