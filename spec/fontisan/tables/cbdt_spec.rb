# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cbdt do
  describe ".read" do
    it "parses CBDT table from binary data" do
      # Create minimal CBDT v2.0 structure:
      # Header: majorVersion(2) + minorVersion(2) + reserved(4) = 8 bytes
      # Bitmap data: variable length

      bitmap_data = "\x89PNG\r\n\x1a\n" + "fake png data"

      header = [
        2, # majorVersion (uint16)
        0, # minorVersion (uint16)
        0, # reserved (uint32)
      ].pack("nnN")

      data = header + bitmap_data

      cbdt = described_class.read(data)

      expect(cbdt.major_version).to eq(2)
      expect(cbdt.minor_version).to eq(0)
      expect(cbdt.version).to eq(0x00020000)
      expect(cbdt.data_size).to eq(data.length)
    end

    it "returns empty table for nil data" do
      cbdt = described_class.read(nil)

      expect(cbdt).to be_a(described_class)
      expect(cbdt.major_version).to be_nil
    end

    it "handles StringIO input" do
      data = [2, 0, 0].pack("nnN")
      io = StringIO.new(data)

      cbdt = described_class.read(io)

      expect(cbdt.major_version).to eq(2)
      expect(cbdt.minor_version).to eq(0)
    end

    it "parses version 3.0 tables" do
      header = [3, 0, 0].pack("nnN")
      cbdt = described_class.read(header)

      expect(cbdt.major_version).to eq(3)
      expect(cbdt.version).to eq(0x00030000)
    end
  end

  describe "#version" do
    it "returns combined version number" do
      data = [2, 0, 0].pack("nnN")
      cbdt = described_class.read(data)

      expect(cbdt.version).to eq(0x00020000)
    end

    it "returns version 3.0" do
      data = [3, 0, 0].pack("nnN")
      cbdt = described_class.read(data)

      expect(cbdt.version).to eq(0x00030000)
    end

    it "returns nil when versions not parsed" do
      cbdt = described_class.new

      expect(cbdt.version).to be_nil
    end
  end

  describe "#major_version" do
    it "returns major version 2" do
      data = [2, 0, 0].pack("nnN")
      cbdt = described_class.read(data)

      expect(cbdt.major_version).to eq(2)
    end

    it "returns major version 3" do
      data = [3, 0, 0].pack("nnN")
      cbdt = described_class.read(data)

      expect(cbdt.major_version).to eq(3)
    end

    it "rejects unsupported major version 1" do
      data = [1, 0, 0].pack("nnN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported CBDT major version/)
    end

    it "rejects unsupported major version 4" do
      data = [4, 0, 0].pack("nnN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported CBDT major version/)
    end
  end

  describe "#minor_version" do
    it "returns minor version 0" do
      data = [2, 0, 0].pack("nnN")
      cbdt = described_class.read(data)

      expect(cbdt.minor_version).to eq(0)
    end

    it "rejects non-zero minor version" do
      data = [2, 1, 0].pack("nnN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported CBDT minor version/)
    end
  end

  describe "#bitmap_data_at" do
    let(:cbdt) do
      bitmap1 = "BITMAP1DATA"
      bitmap2 = "BITMAP2DATA"
      bitmap3 = "BITMAP3DATA"

      header = [2, 0, 0].pack("nnN")
      data = header + bitmap1 + bitmap2 + bitmap3

      described_class.read(data)
    end

    it "extracts bitmap data at offset and length" do
      # Header is 8 bytes, bitmap1 starts at offset 8
      bitmap = cbdt.bitmap_data_at(8, 11)

      expect(bitmap).to eq("BITMAP1DATA")
    end

    it "extracts second bitmap" do
      # bitmap2 starts at offset 8 + 11 = 19
      bitmap = cbdt.bitmap_data_at(19, 11)

      expect(bitmap).to eq("BITMAP2DATA")
    end

    it "extracts third bitmap" do
      # bitmap3 starts at offset 8 + 11 + 11 = 30
      bitmap = cbdt.bitmap_data_at(30, 11)

      expect(bitmap).to eq("BITMAP3DATA")
    end

    it "returns nil for offset beyond data length" do
      bitmap = cbdt.bitmap_data_at(9999, 10)

      expect(bitmap).to be_nil
    end

    it "returns nil for negative offset" do
      bitmap = cbdt.bitmap_data_at(-1, 10)

      expect(bitmap).to be_nil
    end

    it "returns nil for negative length" do
      bitmap = cbdt.bitmap_data_at(8, -1)

      expect(bitmap).to be_nil
    end

    it "returns nil for nil offset" do
      bitmap = cbdt.bitmap_data_at(nil, 10)

      expect(bitmap).to be_nil
    end

    it "returns nil for nil length" do
      bitmap = cbdt.bitmap_data_at(8, nil)

      expect(bitmap).to be_nil
    end

    it "returns nil when offset + length exceeds data size" do
      bitmap = cbdt.bitmap_data_at(30, 50)

      expect(bitmap).to be_nil
    end
  end

  describe "#data_size" do
    it "returns total table size" do
      bitmap_data = "X" * 100
      header = [2, 0, 0].pack("nnN")
      data = header + bitmap_data

      cbdt = described_class.read(data)

      expect(cbdt.data_size).to eq(108) # 8 byte header + 100 bytes data
    end

    it "returns 0 for empty table" do
      cbdt = described_class.new

      expect(cbdt.data_size).to eq(0)
    end

    it "returns size for header-only table" do
      header = [2, 0, 0].pack("nnN")
      cbdt = described_class.read(header)

      expect(cbdt.data_size).to eq(8)
    end
  end

  describe "#valid_offset?" do
    let(:cbdt) do
      header = [2, 0, 0].pack("nnN")
      data = header + ("X" * 100)
      described_class.read(data)
    end

    it "returns true for valid offset" do
      expect(cbdt.valid_offset?(0)).to be true
      expect(cbdt.valid_offset?(50)).to be true
      expect(cbdt.valid_offset?(107)).to be true
    end

    it "returns false for offset at data length" do
      expect(cbdt.valid_offset?(108)).to be false
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

    it "returns false when raw_data is nil" do
      cbdt = described_class.new

      expect(cbdt.valid_offset?(0)).to be false
    end
  end

  describe "#valid?" do
    it "returns true for valid CBDT v2.0 table" do
      header = [2, 0, 0].pack("nnN")
      cbdt = described_class.read(header)

      expect(cbdt.valid?).to be true
    end

    it "returns true for valid CBDT v3.0 table" do
      header = [3, 0, 0].pack("nnN")
      cbdt = described_class.read(header)

      expect(cbdt.valid?).to be true
    end

    it "validates major version" do
      cbdt = described_class.new
      cbdt.instance_variable_set(:@major_version, 1)
      cbdt.instance_variable_set(:@minor_version, 0)
      cbdt.instance_variable_set(:@raw_data, "test")

      expect(cbdt.valid?).to be false
    end

    it "validates minor version is 0" do
      cbdt = described_class.new
      cbdt.instance_variable_set(:@major_version, 2)
      cbdt.instance_variable_set(:@minor_version, 1)
      cbdt.instance_variable_set(:@raw_data, "test")

      expect(cbdt.valid?).to be false
    end

    it "returns false for nil major_version" do
      cbdt = described_class.new
      cbdt.instance_variable_set(:@minor_version, 0)
      cbdt.instance_variable_set(:@raw_data, "test")

      expect(cbdt.valid?).to be false
    end

    it "returns false for nil minor_version" do
      cbdt = described_class.new
      cbdt.instance_variable_set(:@major_version, 2)
      cbdt.instance_variable_set(:@raw_data, "test")

      expect(cbdt.valid?).to be false
    end

    it "returns false for missing raw_data" do
      cbdt = described_class.new
      cbdt.instance_variable_set(:@major_version, 2)
      cbdt.instance_variable_set(:@minor_version, 0)

      expect(cbdt.valid?).to be false
    end
  end

  describe "bitmap data extraction" do
    it "extracts PNG bitmap data" do
      # PNG magic bytes
      png_data = "\x89PNG\r\n\x1a\n" + "\x00" * 100

      header = [2, 0, 0].pack("nnN")
      data = header + png_data

      cbdt = described_class.read(data)
      bitmap = cbdt.bitmap_data_at(8, png_data.length)

      expect(bitmap[0..7]).to eq("\x89PNG\r\n\x1a\n")
      expect(bitmap.length).to eq(png_data.length)
    end

    it "extracts multiple bitmap entries" do
      bitmap1 = "\x89PNG\r\n\x1a\n" + "bitmap1"
      bitmap2 = "\x89PNG\r\n\x1a\n" + "bitmap2"

      header = [2, 0, 0].pack("nnN")
      data = header + bitmap1 + bitmap2

      cbdt = described_class.read(data)

      bmp1 = cbdt.bitmap_data_at(8, bitmap1.length)
      bmp2 = cbdt.bitmap_data_at(8 + bitmap1.length, bitmap2.length)

      expect(bmp1).to eq(bitmap1)
      expect(bmp2).to eq(bitmap2)
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      expect do
        described_class.read("abc")
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse CBDT table/)
    end

    it "raises CorruptedTableError for truncated header" do
      data = [2, 0].pack("nn") # Missing reserved field

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse CBDT table/)
    end
  end
end
