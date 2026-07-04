# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher/partition_strategy"

RSpec.describe Fontisan::Stitcher::PartitionStrategy::ByBlock do
  let(:partitioner) { described_class.new }

  describe "BLOCKS" do
    it "is a frozen Hash of canonical Unicode block names to Ranges" do
      expect(described_class::BLOCKS).to be_a(Hash)
      expect(described_class::BLOCKS).to be_frozen
      expect(described_class::BLOCKS.values).to all(be_a(Range))
    end

    it "includes the major BMP blocks" do
      expect(described_class::BLOCKS).to include(
        "Basic_Latin" => 0x0000..0x007F,
        "Greek_and_Coptic" => 0x0370..0x03FF,
        "CJK_Unified_Ideographs" => 0x4E00..0x9FFF,
        "Hangul_Syllables" => 0xAC00..0xD7AF,
      )
    end

    it "includes the SIP CJK extension blocks" do
      expect(described_class::BLOCKS).to include(
        "CJK_Unified_Ideographs_Extension-B" => 0x20000..0x2A6DF,
        "CJK_Unified_Ideographs_Extension-F" => 0x2CEB0..0x2EBEF,
      )
    end

    it "has no duplicate keys (canonical Unicode block names are unique)" do
      # Each block label must appear exactly once. Duplicates would mean
      # a typo or a copy-paste error in the source data — they'd silently
      # overwrite, leaving codepoints in the dropped range unclassified.
      expect(described_class::BLOCKS.keys.size).to eq(described_class::BLOCKS.keys.uniq.size)
    end

    it "has no overlapping ranges" do
      # In Unicode, each codepoint belongs to exactly one block. If two
      # block ranges overlap, codepoints in the intersection are ambiguous.
      ranges = described_class::BLOCKS.values.sort_by(&:first)
      ranges.each_cons(2) do |a, b|
        expect(a.last).to be < b.first,
                          "block range #{a} overlaps #{b}"
      end
    end
  end

  describe "#call" do
    it "returns an empty Blueprint for empty cp_map" do
      blueprint = partitioner.call({})
      expect(blueprint).to be_a(Fontisan::Stitcher::PartitionStrategy::Blueprint)
      expect(blueprint.partitions).to eq([])
    end

    it "groups codepoints in the same Unicode block into one partition" do
      cp_map = { 0x41 => :latin, 0x42 => :latin } # both in Basic Latin
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to eq([:block_basic_latin])
      expect(blueprint.partitions.first.cps).to contain_exactly(0x41, 0x42)
    end

    it "emits separate partitions per block when codepoints span blocks" do
      cp_map = {
        0x41 => :latin,    # Basic Latin
        0x4E00 => :cjk,    # CJK Unified Ideographs
        0xAC00 => :hangul, # Hangul Syllables
      }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to contain_exactly(
        :block_basic_latin, :block_cjk_unified_ideographs, :block_hangul_syllables
      )
    end

    it "uses :block_other for codepoints not covered by BLOCKS" do
      # Plane 4 is unassigned; codepoints there fall through.
      cp_map = { 0x41 => :latin, 0x40000 => :unassigned }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to contain_exactly(:block_basic_latin, :block_other)
    end

    it "preserves the donor_map for each partition" do
      cp_map = { 0x41 => :donor_a, 0x4E00 => :donor_b }
      blueprint = partitioner.call(cp_map)

      latin = blueprint.partitions.find { |p| p.name == :block_basic_latin }
      expect(latin.donor_map).to eq(0x41 => :donor_a)

      cjk = blueprint.partitions.find { |p| p.name == :block_cjk_unified_ideographs }
      expect(cjk.donor_map).to eq(0x4E00 => :donor_b)
    end

    it "raises PartitionCapExceededError when a single block exceeds cap" do
      # Basic Latin has 128 codepoints. With cap=10, it can't be sub-split.
      cp_map = (0x41..0x50).each_with_index.to_h { |cp, _i| [cp, :donor] }
      expect do
        partitioner.call(cp_map, cap: 10)
      end.to raise_error(Fontisan::PartitionCapExceededError, /single Unicode block/)
    end

    it "names partitions with canonical block labels (downcased, underscored)" do
      cp_map = { 0x2026 => :donor } # General Punctuation
      blueprint = partitioner.call(cp_map)
      expect(blueprint.names).to eq([:block_general_punctuation])
    end
  end
end
