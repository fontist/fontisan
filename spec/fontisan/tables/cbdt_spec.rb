# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cbdt do
  describe ".read" do
    it "parses CBDT table from binary data" do
      bitmap_data = "\x89PNG\r\n\nfake png data"
      header = [3, 0].pack("nn")
      data = header + bitmap_data

      cbdt = described_class.read(data)

      expect(cbdt.major_version).to eq(3)
      expect(cbdt.minor_version).to eq(0)
      expect(cbdt.version).to eq(0x00030000)
      expect(cbdt.data_size).to eq(data.bytesize)
    end

    it "round-trips to identical bytes" do
      data = [2, 0].pack("nn") + ("BITMAP1" * 4)
      cbdt = described_class.read(data)
      expect(cbdt.to_binary_s).to eq(data)
    end

    it "returns empty table for nil data" do
      cbdt = described_class.read(nil)

      expect(cbdt).to be_a(described_class)
      expect(cbdt.has_raw_data?).to be false
      expect(cbdt.data_size).to eq(0)
    end

    it "handles StringIO input" do
      data = [2, 0].pack("nn")
      cbdt = described_class.read(StringIO.new(data))

      expect(cbdt.major_version).to eq(2)
      expect(cbdt.minor_version).to eq(0)
    end

    it "parses version 2.0 tables" do
      cbdt = described_class.read([2, 0].pack("nn"))
      expect(cbdt.major_version).to eq(2)
      expect(cbdt.version).to eq(0x00020000)
    end
  end

  describe "#bitmap_data_at" do
    let(:cbdt) do
      bitmaps = "BITMAP1DATABITMAP2DATABITMAP3DATA"
      described_class.read([2, 0].pack("nn") + bitmaps)
    end

    it "extracts bitmap data at offset and length" do
      expect(cbdt.bitmap_data_at(4, 11)).to eq("BITMAP1DATA")
      expect(cbdt.bitmap_data_at(15, 11)).to eq("BITMAP2DATA")
      expect(cbdt.bitmap_data_at(26, 11)).to eq("BITMAP3DATA")
    end

    it "returns nil for offset beyond data length" do
      expect(cbdt.bitmap_data_at(9999, 10)).to be_nil
    end

    it "returns nil for negative offset" do
      expect(cbdt.bitmap_data_at(-1, 10)).to be_nil
    end

    it "returns nil for negative length" do
      expect(cbdt.bitmap_data_at(4, -1)).to be_nil
    end

    it "returns nil for nil offset or length" do
      expect(cbdt.bitmap_data_at(nil, 10)).to be_nil
      expect(cbdt.bitmap_data_at(4, nil)).to be_nil
    end

    it "returns nil when offset + length exceeds data size" do
      expect(cbdt.bitmap_data_at(33, 50)).to be_nil
    end
  end

  describe "#data_size" do
    it "returns total table size" do
      data = [2, 0].pack("nn") + ("X" * 100)
      cbdt = described_class.read(data)
      expect(cbdt.data_size).to eq(104)
    end

    it "returns 0 for empty table" do
      expect(described_class.new.data_size).to eq(0)
    end

    it "returns size for header-only table" do
      cbdt = described_class.read([2, 0].pack("nn"))
      expect(cbdt.data_size).to eq(4)
    end
  end

  describe "#valid_offset?" do
    let(:cbdt) do
      described_class.read([2, 0].pack("nn") + ("X" * 100))
    end

    it "returns true for valid offsets" do
      expect(cbdt.valid_offset?(0)).to be true
      expect(cbdt.valid_offset?(50)).to be true
      expect(cbdt.valid_offset?(103)).to be true
    end

    it "returns false for offset at data length" do
      expect(cbdt.valid_offset?(104)).to be false
    end

    it "returns false for offset beyond data length" do
      expect(cbdt.valid_offset?(200)).to be false
    end

    it "returns false for negative offset" do
      expect(cbdt.valid_offset?(-1)).to be false
    end

    it "returns false for nil offset" do
      expect(cbdt.valid_offset?(nil)).to be false
    end

    it "returns false on a fresh instance with no data" do
      expect(described_class.new.valid_offset?(0)).to be false
    end
  end

  describe "#valid?" do
    it "returns true for valid CBDT v2.0 table" do
      cbdt = described_class.read([2, 0].pack("nn"))
      expect(cbdt).to be_valid
    end

    it "returns true for valid CBDT v3.0 table" do
      cbdt = described_class.read([3, 0].pack("nn"))
      expect(cbdt).to be_valid
    end

    it "returns false for unsupported major version" do
      cbdt = described_class.read([1, 0].pack("nn"))
      expect(cbdt).not_to be_valid
    end

    it "returns false for unsupported minor version" do
      cbdt = described_class.read([2, 1].pack("nn"))
      expect(cbdt).not_to be_valid
    end

    it "returns false on a fresh instance" do
      expect(described_class.new).not_to be_valid
    end
  end

  describe "PNG extraction" do
    it "extracts PNG bitmap data" do
      png_data = "\x89PNG\r\n\u001A\n#{"\x00" * 100}"
      cbdt = described_class.read([3, 0].pack("nn") + png_data)

      bitmap = cbdt.bitmap_data_at(4, png_data.bytesize)
      expect(bitmap[0..7]).to eq("\x89PNG\r\n\x1a\n")
      expect(bitmap.bytesize).to eq(png_data.bytesize)
    end

    it "extracts multiple bitmap entries" do
      bitmap1 = "\x89PNG\r\n\x1a\nbitmap1"
      bitmap2 = "\x89PNG\r\n\x1a\nbitmap2"
      data = [3, 0].pack("nn") + bitmap1 + bitmap2

      cbdt = described_class.read(data)

      expect(cbdt.bitmap_data_at(4, bitmap1.bytesize)).to eq(bitmap1)
      expect(cbdt.bitmap_data_at(4 + bitmap1.bytesize,
                                 bitmap2.bytesize)).to eq(bitmap2)
    end
  end
end
