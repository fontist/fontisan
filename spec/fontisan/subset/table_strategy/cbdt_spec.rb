# frozen_string_literal: true

require "spec_helper"
require "fontisan/subset/subset_context"
require "fontisan/subset/shared_state"
require "fontisan/subset/table_strategy/cbdt"
require "fontisan/subset/table_strategy/cblc"

RSpec.describe Fontisan::Subset::TableStrategy::Cbdt do
  # Build a single-strike CBLC + CBDT pair covering gids 10..14.
  let(:bitmaps) { %w[AAAA BBBB CCCC DDDD EEEE].map(&:b) }

  let(:cbdt_blob) do
    [3, 0].pack("nn") + bitmaps.join
  end

  let(:cblc_blob) do
    image_data_offset = 4
    offsets = Array.new(bitmaps.length + 1) { |i| (i * 4) / 4 }
    ist = [3, 17, image_data_offset].pack("nnN") + offsets.pack("n*")
    ista = [10, 14, 8].pack("nnN")
    bsm = [56, ista.bytesize + ist.bytesize, 1, 0].pack("NNNN") +
      ("\x00" * 24) + [10, 14, 16, 16, 32, 0].pack("nnCCCc")
    [0x00030000, 1].pack("NN") + bsm + ista + ist
  end

  let(:font) do
    Struct.new(:table_data, keyword_init: true)
      .new(table_data: { "CBDT" => cbdt_blob, "CBLC" => cblc_blob })
  end

  let(:mapping) { Fontisan::Subset::GlyphMapping.new([0, 10, 12]) }

  let(:context) do
    Fontisan::Subset::SubsetContext.new(
      font: font, mapping: mapping, options: nil,
      state: Fontisan::Subset::SharedState.new
    )
  end

  it "returns CBDT bytes that preserve the 4-byte header" do
    bytes = described_class.call(context: context, tag: "CBDT", table: nil)
    expect(bytes[0, 4]).to eq(cbdt_blob[0, 4])
  end

  it "produces a smaller CBDT than the source" do
    bytes = described_class.call(context: context, tag: "CBDT", table: nil)
    expect(bytes.bytesize).to be < cbdt_blob.bytesize
  end

  it "caches the paired subsetter on the shared state" do
    described_class.call(context: context, tag: "CBDT", table: nil)
    cached = context.state.color_bitmap_subsetter
    expect(cached).to be_a(Fontisan::Subset::TableStrategy::ColorBitmapSubsetter)

    cblc_bytes = Fontisan::Subset::TableStrategy::Cblc.call(
      context: context, tag: "CBLC", table: nil,
    )
    expect(cblc_bytes).to eq(cached.cblc_bytes)
  end
end
