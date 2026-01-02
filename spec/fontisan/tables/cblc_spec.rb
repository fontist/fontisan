# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cblc do
  describe ".read" do
    it "parses CBLC table from binary data" do
      # Create minimal CBLC v2.0 structure:
      # Header: version(4) + numSizes(4) = 8 bytes
      # BitmapSize records: 2 × 48 bytes = 96 bytes

      header = [
        0x00020000, # version 2.0 (uint32)
        2,          # numSizes (uint32)
      ].pack("NN")

      # BitmapSize record 1 (48 bytes)
      size1 = create_bitmap_size(
        offset: 1000, size: 500, num_subtables: 3,
        start_glyph: 10, end_glyph: 20, ppem: 16, bit_depth: 8,
      )

      # BitmapSize record 2 (48 bytes)
      size2 = create_bitmap_size(
        offset: 2000, size: 600, num_subtables: 5,
        start_glyph: 30, end_glyph: 40, ppem: 32, bit_depth: 32,
      )

      data = header + size1 + size2

      cblc = described_class.read(data)

      expect(cblc.version).to eq(0x00020000)
      expect(cblc.num_sizes).to eq(2)
      expect(cblc.bitmap_sizes.length).to eq(2)
      expect(cblc.bitmap_sizes[0].start_glyph_index).to eq(10)
      expect(cblc.bitmap_sizes[0].end_glyph_index).to eq(20)
      expect(cblc.bitmap_sizes[0].ppem_x).to eq(16)
      expect(cblc.bitmap_sizes[1].ppem_y).to eq(32)
    end

    it "returns empty table for nil data" do
      cblc = described_class.read(nil)

      expect(cblc).to be_a(described_class)
      expect(cblc.version).to be_nil
    end

    it "handles StringIO input" do
      data = [0x00020000, 0].pack("NN")
      io = StringIO.new(data)

      cblc = described_class.read(io)

      expect(cblc.version).to eq(0x00020000)
    end

    it "parses version 3.0 tables" do
      header = [0x00030000, 1].pack("NN")
      size = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 0, end_glyph: 10, ppem: 12, bit_depth: 1,
      )
      data = header + size

      cblc = described_class.read(data)

      expect(cblc.version).to eq(0x00030000)
      expect(cblc.num_sizes).to eq(1)
    end
  end

  describe "#version" do
    it "returns CBLC version number" do
      data = [0x00020000, 0].pack("NN")
      cblc = described_class.read(data)

      expect(cblc.version).to eq(0x00020000)
    end

    it "rejects unsupported version 1.0" do
      data = [0x00010000, 0].pack("NN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported CBLC version/)
    end

    it "rejects unsupported version 4.0" do
      data = [0x00040000, 0].pack("NN")

      expect do
        described_class.read(data)
      end.to raise_error(Fontisan::CorruptedTableError, /Unsupported CBLC version/)
    end
  end

  describe "#strikes" do
    let(:cblc) do
      header = [0x00020000, 2].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      data = header + size1 + size2
      described_class.read(data)
    end

    it "returns all bitmap size records" do
      strikes = cblc.strikes

      expect(strikes.length).to eq(2)
      expect(strikes[0]).to be_a(described_class::BitmapSize)
      expect(strikes[1]).to be_a(described_class::BitmapSize)
    end

    it "returns empty array for table with no sizes" do
      data = [0x00020000, 0].pack("NN")
      cblc = described_class.read(data)

      expect(cblc.strikes).to eq([])
    end
  end

  describe "#strikes_for_ppem" do
    let(:cblc) do
      header = [0x00020000, 3].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      size3 = create_bitmap_size(
        offset: 300, size: 70, num_subtables: 1,
        start_glyph: 30, end_glyph: 35, ppem: 16, bit_depth: 8,
      )
      data = header + size1 + size2 + size3
      described_class.read(data)
    end

    it "returns strikes matching ppem size" do
      strikes = cblc.strikes_for_ppem(16)

      expect(strikes.length).to eq(2)
      expect(strikes[0].ppem).to eq(16)
      expect(strikes[1].ppem).to eq(16)
    end

    it "returns single strike when only one matches" do
      strikes = cblc.strikes_for_ppem(32)

      expect(strikes.length).to eq(1)
      expect(strikes[0].ppem).to eq(32)
    end

    it "returns empty array when no strikes match" do
      strikes = cblc.strikes_for_ppem(64)

      expect(strikes).to eq([])
    end
  end

  describe "#has_bitmap_for_glyph?" do
    let(:cblc) do
      header = [0x00020000, 2].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      data = header + size1 + size2
      described_class.read(data)
    end

    it "returns true when glyph has bitmap at ppem" do
      expect(cblc.has_bitmap_for_glyph?(10, 16)).to be true
      expect(cblc.has_bitmap_for_glyph?(15, 16)).to be true
      expect(cblc.has_bitmap_for_glyph?(20, 32)).to be true
    end

    it "returns false when glyph doesn't have bitmap at ppem" do
      expect(cblc.has_bitmap_for_glyph?(10, 32)).to be false
      expect(cblc.has_bitmap_for_glyph?(20, 16)).to be false
    end

    it "returns false for non-existent glyph" do
      expect(cblc.has_bitmap_for_glyph?(999, 16)).to be false
    end

    it "returns false for non-existent ppem" do
      expect(cblc.has_bitmap_for_glyph?(10, 64)).to be false
    end
  end

  describe "#ppem_sizes" do
    it "returns sorted unique ppem sizes" do
      header = [0x00020000, 4].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      size3 = create_bitmap_size(
        offset: 300, size: 70, num_subtables: 1,
        start_glyph: 30, end_glyph: 35, ppem: 16, bit_depth: 8,
      )
      size4 = create_bitmap_size(
        offset: 400, size: 80, num_subtables: 1,
        start_glyph: 40, end_glyph: 45, ppem: 64, bit_depth: 8,
      )
      data = header + size1 + size2 + size3 + size4

      cblc = described_class.read(data)
      sizes = cblc.ppem_sizes

      expect(sizes).to eq([16, 32, 64])
    end

    it "returns empty array for table with no sizes" do
      data = [0x00020000, 0].pack("NN")
      cblc = described_class.read(data)

      expect(cblc.ppem_sizes).to eq([])
    end
  end

  describe "#glyph_ids_with_bitmaps" do
    it "returns sorted unique glyph IDs" do
      header = [0x00020000, 2].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 12, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 21, ppem: 32, bit_depth: 32,
      )
      data = header + size1 + size2

      cblc = described_class.read(data)
      ids = cblc.glyph_ids_with_bitmaps

      expect(ids).to eq([10, 11, 12, 20, 21])
    end

    it "handles overlapping glyph ranges" do
      header = [0x00020000, 2].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 12, end_glyph: 18, ppem: 32, bit_depth: 32,
      )
      data = header + size1 + size2

      cblc = described_class.read(data)
      ids = cblc.glyph_ids_with_bitmaps

      expect(ids).to eq([10, 11, 12, 13, 14, 15, 16, 17, 18])
    end

    it "returns empty array for table with no sizes" do
      data = [0x00020000, 0].pack("NN")
      cblc = described_class.read(data)

      expect(cblc.glyph_ids_with_bitmaps).to eq([])
    end
  end

  describe "#strikes_for_glyph" do
    let(:cblc) do
      header = [0x00020000, 3].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 20, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 15, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      size3 = create_bitmap_size(
        offset: 300, size: 70, num_subtables: 1,
        start_glyph: 30, end_glyph: 40, ppem: 64, bit_depth: 8,
      )
      data = header + size1 + size2 + size3
      described_class.read(data)
    end

    it "returns all strikes containing glyph" do
      strikes = cblc.strikes_for_glyph(17)

      expect(strikes.length).to eq(2)
      expect(strikes[0].ppem).to eq(16)
      expect(strikes[1].ppem).to eq(32)
    end

    it "returns single strike when glyph in one strike" do
      strikes = cblc.strikes_for_glyph(35)

      expect(strikes.length).to eq(1)
      expect(strikes[0].ppem).to eq(64)
    end

    it "returns empty array for non-existent glyph" do
      strikes = cblc.strikes_for_glyph(999)

      expect(strikes).to eq([])
    end
  end

  describe "#num_strikes" do
    it "returns number of bitmap sizes" do
      header = [0x00020000, 3].pack("NN")
      size1 = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      size2 = create_bitmap_size(
        offset: 200, size: 60, num_subtables: 2,
        start_glyph: 20, end_glyph: 25, ppem: 32, bit_depth: 32,
      )
      size3 = create_bitmap_size(
        offset: 300, size: 70, num_subtables: 1,
        start_glyph: 30, end_glyph: 35, ppem: 64, bit_depth: 8,
      )
      data = header + size1 + size2 + size3

      cblc = described_class.read(data)

      expect(cblc.num_strikes).to eq(3)
    end

    it "returns 0 for table with no sizes" do
      data = [0x00020000, 0].pack("NN")
      cblc = described_class.read(data)

      expect(cblc.num_strikes).to eq(0)
    end
  end

  describe "#valid?" do
    it "returns true for valid CBLC v2.0 table" do
      header = [0x00020000, 1].pack("NN")
      size = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      data = header + size

      cblc = described_class.read(data)

      expect(cblc.valid?).to be true
    end

    it "returns true for valid CBLC v3.0 table" do
      header = [0x00030000, 1].pack("NN")
      size = create_bitmap_size(
        offset: 100, size: 50, num_subtables: 1,
        start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
      )
      data = header + size

      cblc = described_class.read(data)

      expect(cblc.valid?).to be true
    end

    it "validates version number" do
      cblc = described_class.new
      cblc.instance_variable_set(:@version, 0x00010000)
      cblc.instance_variable_set(:@num_sizes, 0)
      cblc.instance_variable_set(:@bitmap_sizes, [])

      expect(cblc.valid?).to be false
    end

    it "validates num_sizes is non-negative" do
      cblc = described_class.new
      cblc.instance_variable_set(:@version, 0x00020000)
      cblc.instance_variable_set(:@num_sizes, -1)
      cblc.instance_variable_set(:@bitmap_sizes, [])

      expect(cblc.valid?).to be false
    end

    it "returns false for nil version" do
      cblc = described_class.new

      expect(cblc.valid?).to be false
    end

    it "returns false for missing bitmap_sizes" do
      cblc = described_class.new
      cblc.instance_variable_set(:@version, 0x00020000)
      cblc.instance_variable_set(:@num_sizes, 1)

      expect(cblc.valid?).to be false
    end
  end

  describe "BitmapSize" do
    describe "#ppem" do
      it "returns ppem_x value" do
        size_data = create_bitmap_size(
          offset: 100, size: 50, num_subtables: 1,
          start_glyph: 10, end_glyph: 15, ppem: 16, bit_depth: 8,
        )
        size = described_class::BitmapSize.read(size_data)

        expect(size.ppem).to eq(16)
      end
    end

    describe "#glyph_range" do
      it "returns range of glyph IDs" do
        size_data = create_bitmap_size(
          offset: 100, size: 50, num_subtables: 1,
          start_glyph: 10, end_glyph: 20, ppem: 16, bit_depth: 8,
        )
        size = described_class::BitmapSize.read(size_data)

        expect(size.glyph_range).to eq(10..20)
      end
    end

    describe "#includes_glyph?" do
      let(:size) do
        size_data = create_bitmap_size(
          offset: 100, size: 50, num_subtables: 1,
          start_glyph: 10, end_glyph: 20, ppem: 16, bit_depth: 8,
        )
        described_class::BitmapSize.read(size_data)
      end

      it "returns true for glyph in range" do
        expect(size.includes_glyph?(10)).to be true
        expect(size.includes_glyph?(15)).to be true
        expect(size.includes_glyph?(20)).to be true
      end

      it "returns false for glyph outside range" do
        expect(size.includes_glyph?(9)).to be false
        expect(size.includes_glyph?(21)).to be false
        expect(size.includes_glyph?(999)).to be false
      end
    end
  end

  describe "error handling" do
    it "raises CorruptedTableError for invalid data" do
      expect do
        described_class.read("abc")
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse CBLC table/)
    end

    it "raises CorruptedTableError for truncated data" do
      header = [0x00020000, 1].pack("NN")
      size_partial = "abc" # Not 48 bytes

      expect do
        described_class.read(header + size_partial)
      end.to raise_error(Fontisan::CorruptedTableError, /Failed to parse CBLC table/)
    end
  end

  # Helper method to create BitmapSize record (48 bytes)
  def create_bitmap_size(offset:, size:, num_subtables:, start_glyph:, end_glyph:, ppem:, bit_depth:)
    [
      offset,         # indexSubTableArrayOffset (uint32)
      size,           # indexTablesSize (uint32)
      num_subtables,  # numberOfIndexSubTables (uint32)
      0,              # colorRef (uint32)
    ].pack("NNNN") +
      "\x00" * 12 +   # hori SbitLineMetrics (12 bytes)
      "\x00" * 12 +   # vert SbitLineMetrics (12 bytes)
      [
        start_glyph,  # startGlyphIndex (uint16)
        end_glyph,    # endGlyphIndex (uint16)
        ppem,         # ppemX (uint8)
        ppem,         # ppemY (uint8)
        bit_depth,    # bitDepth (uint8)
        0,            # flags (int8)
      ].pack("nnCCCc")
  end
end
