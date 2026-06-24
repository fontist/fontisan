# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/codepoint_range_coalescer"

RSpec.describe Fontisan::Audit::CodepointRangeCoalescer do
  it "returns an empty array for nil input" do
    expect(described_class.call(nil)).to eq([])
  end

  it "returns an empty array for empty input" do
    expect(described_class.call([])).to eq([])
  end

  it "produces a single-codepoint range for one input" do
    ranges = described_class.call([0x0041])
    expect(ranges.length).to eq(1)
    expect(ranges.first.first_cp).to eq(0x0041)
    expect(ranges.first.last_cp).to eq(0x0041)
    expect(ranges.first.to_s).to eq("U+0041")
  end

  it "coalesces a contiguous run into one range" do
    ranges = described_class.call((0x0020..0x007E).to_a)
    expect(ranges.length).to eq(1)
    expect(ranges.first.first_cp).to eq(0x0020)
    expect(ranges.first.last_cp).to eq(0x007E)
  end

  it "splits disjoint runs into separate ranges" do
    ranges = described_class.call([0x0041, 0x0042, 0x0080, 0x0081])
    expect(ranges.length).to eq(2)
    expect(ranges.map(&:to_s)).to eq(["U+0041-U+0042", "U+0080-U+0081"])
  end

  it "sorts unsorted input" do
    ranges = described_class.call([0x0080, 0x0041, 0x0042])
    expect(ranges.map(&:first_cp)).to eq([0x0041, 0x0080])
  end

  it "deduplicates input" do
    ranges = described_class.call([0x0041, 0x0041, 0x0042, 0x0042])
    expect(ranges.length).to eq(1)
    expect(ranges.first.first_cp).to eq(0x0041)
    expect(ranges.first.last_cp).to eq(0x0042)
  end

  it "produces many ranges for a fragmented set" do
    ranges = described_class.call([0x0041, 0x0043, 0x0045, 0x0047])
    expect(ranges.length).to eq(4)
    expect(ranges.map(&:to_s)).to eq(
      ["U+0041", "U+0043", "U+0045", "U+0047"],
    )
  end

  it "handles a large CJK-style range quickly" do
    cps = (0x4E00..0x9FFF).to_a
    ranges = described_class.call(cps)
    expect(ranges.length).to eq(1)
    expect(ranges.first.first_cp).to eq(0x4E00)
    expect(ranges.first.last_cp).to eq(0x9FFF)
  end
end
