# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/aggregator"
require "fontisan/ucd/index"
require "fontisan/ucd/range_entry"

RSpec.describe Fontisan::Ucd::Aggregator do
  let(:blocks_entries) do
    [
      Fontisan::Ucd::RangeEntry.new(0x0000, 0x007F, "Basic Latin"),
      Fontisan::Ucd::RangeEntry.new(0x0080, 0x00FF, "Latin-1 Supplement"),
      Fontisan::Ucd::RangeEntry.new(0x0100, 0x017F, "Latin Extended-A"),
    ]
  end

  let(:scripts_entries) do
    [
      Fontisan::Ucd::RangeEntry.new(0x0041, 0x005A, "Latin"),
      Fontisan::Ucd::RangeEntry.new(0x0061, 0x007A, "Latin"),
      Fontisan::Ucd::RangeEntry.new(0x0391, 0x03A9, "Greek"),
      Fontisan::Ucd::RangeEntry.new(0x0410, 0x044F, "Cyrillic"),
    ]
  end

  let(:blocks_index) { Fontisan::Ucd::Index.new(blocks_entries) }
  let(:scripts_index) { Fontisan::Ucd::Index.new(scripts_entries) }

  describe ".aggregate_blocks" do
    it "returns one hash per overlapping block" do
      codepoints = (0x41..0x5A).to_a + [0xA0]
      result = described_class.aggregate_blocks(codepoints, blocks_index)

      expect(result.length).to eq(2)
      names = result.map { |h| h[:name] }
      expect(names).to contain_exactly("Basic Latin", "Latin-1 Supplement")
    end

    it "counts covered vs total correctly" do
      codepoints = (0x41..0x5A).to_a
      result = described_class.aggregate_blocks(codepoints, blocks_index)

      basic_latin = result.find { |h| h[:name] == "Basic Latin" }
      expect(basic_latin[:total]).to eq(0x80)
      expect(basic_latin[:covered]).to eq(26)
      expect(basic_latin[:complete]).to be false
      expect(basic_latin[:fill_ratio]).to be_within(0.001).of(26.fdiv(128))
    end

    it "marks complete when fully covered" do
      codepoints = (0x00..0x7F).to_a
      result = described_class.aggregate_blocks(codepoints, blocks_index)
      basic_latin = result.find { |h| h[:name] == "Basic Latin" }

      expect(basic_latin[:complete]).to be true
      expect(basic_latin[:fill_ratio]).to eq(1.0)
    end

    it "returns empty array for empty codepoints" do
      result = described_class.aggregate_blocks([], blocks_index)
      expect(result).to eq([])
    end

    it "returns empty array when codepoints are outside any block" do
      result = described_class.aggregate_blocks([0x10000], blocks_index)
      expect(result).to eq([])
    end

    it "includes first_cp and last_cp in each block hash" do
      result = described_class.aggregate_blocks([0x41], blocks_index)
      basic_latin = result.first
      expect(basic_latin[:first_cp]).to eq(0x0000)
      expect(basic_latin[:last_cp]).to eq(0x007F)
    end
  end

  describe ".aggregate_scripts" do
    it "returns unique sorted script names" do
      codepoints = [0x41, 0x61, 0x391, 0x410] # Latin A, Latin a, Greek Alpha, Cyrillic A
      result = described_class.aggregate_scripts(codepoints, scripts_index)

      expect(result).to eq(["Cyrillic", "Greek", "Latin"])
    end

    it "skips codepoints not in any script range" do
      codepoints = [0x41, 0x9999] # 0x9999 not in any range
      result = described_class.aggregate_scripts(codepoints, scripts_index)
      expect(result).to eq(["Latin"])
    end

    it "returns empty array for empty codepoints" do
      expect(described_class.aggregate_scripts([], scripts_index)).to eq([])
    end
  end
end
