# frozen_string_literal: true

require "spec_helper"
require "bindata"

RSpec.describe Fontisan::Tables::Cblc do
  # Helper: build a single-strike CBLC + CBDT pair for the given glyph
  # range. The CBDT bitmaps are 4-byte aligned so format 3 offsets stay
  # valid.
  def build_cblc(bitmaps:, version: 0x00030000, first_gid: 10, last_gid: 12,
                 ppem: 16, bit_depth: 32, image_format: 17)
    bitmap_size = (last_gid - first_gid + 1)
    image_size = bitmaps.first.bytesize

    # CBDT: 4-byte header + concatenated bitmaps
    cbdt = [3, 0].pack("nn") + bitmaps.map(&:b).join

    # IndexSubTable format 3: 8-byte header + uint16 offsetArray[count+1]
    # (offsets are stored as multiples of 4 since bitmap data is 4-byte
    # aligned). imageDataOffset = 4 (start of bitmap data after CBDT header).
    offsets = Array.new(bitmap_size + 1) { |i| (i * image_size) / 4 }
    ist = [3, image_format, 4].pack("nnN") + offsets.pack("n*")
    # IndexSubTableArray entry: first, last, additionalOffset (relative to
    # array start; 8 bytes from array start = past this single entry).
    ista = [first_gid, last_gid, 8].pack("nnN")

    bsm_offset = 8 + 48
    bsm_size = ista.bytesize + ist.bytesize
    bsm = [
      bsm_offset, bsm_size, 1, 0 # offset, size, numSubTables, colorRef
    ].pack("NNNN") + ("\x00" * 24) + [
      first_gid, last_gid, ppem, ppem, bit_depth, 0
    ].pack("nnCCCc")

    cblc = [version, 1].pack("NN") + bsm + ista + ist
    [cblc, cbdt]
  end

  describe ".read" do
    it "parses a CBLC v3.0 table with one strike" do
      cblc_bytes, = build_cblc(bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)

      expect(cblc.version).to eq(0x00030000)
      expect(cblc.num_sizes).to eq(1)
      expect(cblc.bitmap_sizes.length).to eq(1)
      strike = cblc.bitmap_sizes[0]
      expect(strike.start_glyph_index).to eq(10)
      expect(strike.end_glyph_index).to eq(12)
      expect(strike.ppem_x).to eq(16)
      expect(strike.bit_depth).to eq(32)
    end

    it "parses a CBLC v2.0 table" do
      cblc_bytes, = build_cblc(version: 0x00020000,
                               bitmaps: %w[AAAA])
      cblc = described_class.read(cblc_bytes)
      expect(cblc.version).to eq(0x00020000)
    end
  end

  describe "#each_glyph_location" do
    it "yields one location per glyph across every strike" do
      cblc_bytes, _cbdt = build_cblc(bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)

      locations = cblc.each_glyph_location.to_a

      expect(locations.length).to eq(3)
      expect(locations.map(&:glyph_id)).to eq([10, 11, 12])
      expect(locations.map(&:byte_length)).to eq([4, 4, 4])
      expect(locations.map(&:image_format).uniq).to eq([17])
    end
  end

  describe "#bitmap_offset_for_gid" do
    it "returns the location for a glyph in the strike" do
      cblc_bytes, = build_cblc(bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)

      loc = cblc.bitmap_offset_for_gid(11, 16)
      expect(loc.glyph_id).to eq(11)
      expect(loc.cbdt_offset).to eq(8) # header(4) + one bitmap
      expect(loc.byte_length).to eq(4)
    end

    it "returns nil for an out-of-range glyph" do
      cblc_bytes, = build_cblc(bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)

      expect(cblc.bitmap_offset_for_gid(999, 16)).to be_nil
    end

    it "returns nil when no strike matches the ppem" do
      cblc_bytes, = build_cblc(ppem: 16, bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)

      expect(cblc.bitmap_offset_for_gid(10, 32)).to be_nil
    end
  end

  describe "BitmapSize accessors" do
    let(:cblc) do
      bytes, = build_cblc(first_gid: 10, last_gid: 11, ppem: 16,
                          bit_depth: 32, bitmaps: %w[AAAA BBBB])
      described_class.read(bytes)
    end

    it "exposes ppem, glyph range, and inclusion test" do
      strike = cblc.bitmap_sizes[0]
      expect(strike.ppem).to eq(16)
      expect(strike.glyph_range).to eq(10..11)
      expect(strike.includes_glyph?(10)).to be true
      expect(strike.includes_glyph?(12)).to be false
    end
  end

  describe "#ppem_sizes" do
    it "returns sorted unique ppem sizes" do
      cblc_bytes, = build_cblc(ppem: 16, bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)
      expect(cblc.ppem_sizes).to eq([16])
    end
  end

  describe "#strikes_for_glyph and #strikes_for_ppem" do
    it "returns the matching strikes" do
      cblc_bytes, = build_cblc(ppem: 16, bitmaps: %w[AAAA BBBB])
      cblc = described_class.read(cblc_bytes)

      expect(cblc.strikes_for_glyph(10).map(&:ppem)).to eq([16])
      expect(cblc.strikes_for_glyph(99)).to eq([])
      expect(cblc.strikes_for_ppem(16).length).to eq(1)
      expect(cblc.strikes_for_ppem(32)).to eq([])
    end
  end

  describe "#glyph_ids_with_bitmaps" do
    it "returns sorted unique glyph IDs" do
      cblc_bytes, = build_cblc(first_gid: 10, last_gid: 12,
                               bitmaps: %w[AAAA BBBB CCCC])
      cblc = described_class.read(cblc_bytes)
      expect(cblc.glyph_ids_with_bitmaps).to eq([10, 11, 12])
    end
  end

  describe "#valid?" do
    it "returns true for a v3.0 table" do
      cblc_bytes, = build_cblc(bitmaps: %w[AAAA BBBB])
      expect(described_class.read(cblc_bytes)).to be_valid
    end

    it "returns true for a v2.0 table" do
      cblc_bytes, = build_cblc(version: 0x00020000, bitmaps: %w[AAAA])
      expect(described_class.read(cblc_bytes)).to be_valid
    end

    it "returns false for an unsupported version" do
      cblc = described_class.new
      cblc.version = 0x00010000
      expect(cblc).not_to be_valid
    end
  end
end
