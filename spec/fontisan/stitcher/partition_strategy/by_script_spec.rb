# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher/partition_strategy"

RSpec.describe Fontisan::Stitcher::PartitionStrategy::ByScript do
  let(:partitioner) { described_class.new }

  describe "SCRIPT_OF_BLOCK" do
    it "is a frozen Hash mapping block labels to script symbols" do
      expect(described_class::SCRIPT_OF_BLOCK).to be_a(Hash)
      expect(described_class::SCRIPT_OF_BLOCK).to be_frozen
      expect(described_class::SCRIPT_OF_BLOCK.values).to all(be_a(Symbol))
    end

    it "maps every CJK ideograph extension block to :han" do
      cjk_blocks = described_class::SCRIPT_OF_BLOCK.select { |_k, v| v == :han }
      expect(cjk_blocks.keys).to include(
        "CJK_Unified_Ideographs",
        "CJK_Unified_Ideographs_Extension_A",
        "CJK_Unified_Ideographs_Extension_B",
      )
    end

    it "has no duplicate keys" do
      keys = described_class::SCRIPT_OF_BLOCK.keys
      expect(keys.size).to eq(keys.uniq.size)
    end
  end

  describe "#call" do
    it "returns an empty Blueprint for empty cp_map" do
      blueprint = partitioner.call({})
      expect(blueprint.partitions).to eq([])
    end

    it "groups codepoints by script across multiple blocks" do
      # Basic Latin (Common for ASCII letters per Unicode), Latin-1 Supplement
      # (Latin), Latin Extended-A (Latin) — three blocks, two scripts.
      cp_map = {
        0x41 => :a,           # Basic Latin
        0xC0 => :a_grave,     # Latin-1 Supplement (À)
        0x100 => :a_macron,   # Latin Extended-A (Ā)
      }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to contain_exactly(:script_common, :script_latin)
    end

    it "emits separate partitions per script" do
      cp_map = {
        0x41 => :latin,       # Basic Latin → :common
        0x4E00 => :cjk,       # CJK Unified Ideographs → :han
        0xAC00 => :hangul,    # Hangul Syllables → :hangul
      }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to contain_exactly(:script_common, :script_han,
                                                 :script_hangul)
    end

    it "uses :script_other for codepoints in unmapped blocks" do
      cp_map = { 0x40000 => :unassigned } # Plane 4
      blueprint = partitioner.call(cp_map)
      expect(blueprint.names).to eq([:script_other])
    end

    it "chunks scripts that overflow cap with alphabetic suffixes" do
      # 6 Han codepoints, cap=2 → 3 chunks.
      cp_map = (0x4E00..0x4E05).each_with_index.to_h { |cp, _i| [cp, :cjk] }
      blueprint = partitioner.call(cp_map, cap: 2)

      expect(blueprint.names).to eq(%i[script_han script_han_a script_han_b])
      all_cps = blueprint.partitions.flat_map(&:cps)
      expect(all_cps).to contain_exactly(0x4E00, 0x4E01, 0x4E02, 0x4E03,
                                         0x4E04, 0x4E05)
    end

    it "names Common and Inherited scripts explicitly" do
      cp_map = {
        0x30 => :digit,       # Basic Latin digit → Common
        0x0300 => :combining, # Combining Diacritical Marks → Inherited
      }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to contain_exactly(:script_common,
                                                 :script_inherited)
    end

    it "preserves the donor_map for each partition" do
      cp_map = { 0x41 => :donor_a, 0x4E00 => :donor_b }
      blueprint = partitioner.call(cp_map)

      common = blueprint.partitions.find { |p| p.name == :script_common }
      expect(common.donor_map).to eq(0x41 => :donor_a)

      han = blueprint.partitions.find { |p| p.name == :script_han }
      expect(han.donor_map).to eq(0x4E00 => :donor_b)
    end
  end
end
