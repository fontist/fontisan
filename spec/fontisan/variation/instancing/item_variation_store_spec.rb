# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Variation::Instancing::ItemVariationStore do
  # One axis, one region (start 0, peak 1, end 1), two items: +10 and -20.
  let(:store) do
    region_list = [1, 1].pack("nn") + [0, 16_384, 16_384].pack("s>3")
    data = [2, 1, 1, 0].pack("nnnn") + [10, -20].pack("s>2")
    header = [1, 12, 1, 12 + region_list.bytesize].pack("nNnN")
    header + region_list + data
  end

  def hvar(advance_map: nil)
    map_offset = advance_map ? 20 + store.bytesize : 0
    [1, 0, 20, map_offset, 0, 0].pack("nnNNNN") + store + advance_map.to_s
  end

  it "applies the region scalar to an item's delta" do
    ivs = described_class.new(hvar)
    expect(ivs.advance_delta(0, [1.0])).to eq(10)
    expect(ivs.advance_delta(1, [1.0])).to eq(-20)
    expect(ivs.advance_delta(1, [0.5])).to eq(-10)
  end

  it "has no delta at the default location or outside the region" do
    ivs = described_class.new(hvar)
    expect(ivs.advance_delta(1, [0.0])).to eq(0)
    expect(ivs.advance_delta(1, [-0.5])).to eq(0)
  end

  it "resolves glyph ids through an advance-width DeltaSetIndexMap" do
    # format 0, entryFormat 0 (1 inner bit, 1 byte): gid0 -> item 1, gid1 -> item 0
    map = [0, 0, 2].pack("CCn") + [1, 0].pack("CC")
    ivs = described_class.new(hvar(advance_map: map))
    expect(ivs.advance_delta(0, [1.0])).to eq(-20)
    expect(ivs.advance_delta(1, [1.0])).to eq(10)
  end
end
