# frozen_string_literal: true

require "spec_helper"

# Shared helper: build a single-strike CBLC + CBDT pair covering a
# contiguous glyph range. Bitmaps are 4-byte aligned so format 3
# offsets stay valid in the source. Format 17 = small metrics + PNG
# image, the NotoColorEmoji layout.
module ColorBitmapSpecHelpers
  def build_color_font(bitmaps:, first_gid: 10, last_gid: 14, ppem: 16,
image_format: 17, version: 0x00030000)
    count = bitmaps.length
    raise ArgumentError unless count == last_gid - first_gid + 1

    cbd_header = [3, 0].pack("nn")
    cbdt_blob = cbd_header + bitmaps.join

    # Build IndexSubTable format 3: header(8) + uint16 offsetArray[count+1]
    # offsets stored as multiples of 4 (4-byte aligned). imageDataOffset
    # = 4 (start of bitmap data after CBDT 4-byte header).
    image_data_offset = 4
    offsets_raw = Array.new(count + 1) do |i|
      (i * bitmaps.first.bytesize) / 4
    end
    ist = [3, image_format, image_data_offset].pack("nnN") +
      offsets_raw.pack("n*")
    ista = [first_gid, last_gid, 8].pack("nnN")

    bsm_offset = 8 + 48
    bsm_size = ista.bytesize + ist.bytesize
    bsm = [bsm_offset, bsm_size, 1, 0].pack("NNNN") +
      ("\x00" * 24) +
      [first_gid, last_gid, ppem, ppem, 32, 0].pack("nnCCCc")

    cblc_blob = [version, 1].pack("NN") + bsm + ista + ist
    [cblc_blob, cbdt_blob]
  end

  # Build a minimal font-like object exposing only the API the
  # ColorBitmapSubsetter needs: table_data returns CBDT/CBLC bytes.
  TestFont = Struct.new(:table_data, keyword_init: true)

  def build_test_font(cbdt:, cblc:)
    TestFont.new(table_data: { "CBDT" => cbdt, "CBLC" => cblc })
  end
end

RSpec.describe Fontisan::Subset::TableStrategy::ColorBitmapSubsetter do
  include ColorBitmapSpecHelpers

  describe "subset of a 2-emoji range from a 5-emoji source" do
    subject(:subsetter) do
      described_class.new(font: font, mapping: mapping).build
    end

    let(:bitmaps) do
      %w[AAAA BBBB CCCC DDDD EEEE].map(&:b)
    end

    let(:cblc_blob) do
      build_color_font(first_gid: 10, last_gid: 14,
                       bitmaps: bitmaps).first
    end
    let(:cbdt_blob) do
      build_color_font(first_gid: 10, last_gid: 14,
                       bitmaps: bitmaps).last
    end
    let(:font) { build_test_font(cbdt: cbdt_blob, cblc: cblc_blob) }

    # Source gids [0, 10, 12] → subset retains only those; gid 0
    # (.notdef) is not in CBLC.
    let(:mapping) { Fontisan::Subset::GlyphMapping.new([0, 10, 12]) }

    it "produces a smaller CBDT than the source" do
      expect(subsetter.cbdt_bytes.bytesize).to be < cbdt_blob.bytesize
    end

    it "preserves the 4-byte CBDT header" do
      expect(subsetter.cbdt_bytes[0, 4]).to eq(cbdt_blob[0, 4])
    end

    it "includes exactly the retained bitmaps in the new CBDT body" do
      body = subsetter.cbdt_bytes[4..]
      expect(body).to eq("AAAACCCC")
    end

    it "produces a CBLC whose version matches the source" do
      version = subsetter.cblc_bytes[0, 4].unpack1("N")
      expect(version).to eq(0x00030000)
    end

    it "reports one surviving strike in the new CBLC" do
      num_sizes = subsetter.cblc_bytes[4, 4].unpack1("N")
      expect(num_sizes).to eq(1)
    end

    it "round-trips the new CBLC through Tables::Cblc.read" do
      rebuilt = Fontisan::Tables::Cblc.read(subsetter.cblc_bytes)
      expect(rebuilt.bitmap_sizes.length).to eq(1)
    end

    it "the new CBLC's surviving IndexSubTable covers only retained new gids" do
      rebuilt = Fontisan::Tables::Cblc.read(subsetter.cblc_bytes)
      gids = rebuilt.each_glyph_location.map(&:glyph_id).sort
      # mapping [0, 10, 12] → compact new ids [0, 1, 2]; gid 0 isn't in
      # CBLC, so only the new GIDs for source 10 and 12 appear.
      expect(gids).to eq([1, 2])
    end
  end

  describe "with no CBDT/CBLC in the source" do
    include ColorBitmapSpecHelpers

    let(:font) { build_test_font(cbdt: nil, cblc: nil) }
    let(:mapping) { Fontisan::Subset::GlyphMapping.new([0]) }

    it "emits empty CBDT and CBLC strings" do
      subsetter = described_class.new(font: font, mapping: mapping).build
      expect(subsetter.cbdt_bytes).to eq("")
      expect(subsetter.cblc_bytes).to eq("")
    end
  end
end
