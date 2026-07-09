# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher/partition_strategy"

RSpec.describe Fontisan::Stitcher::PartitionStrategy::ByPlane do
  let(:partitioner) { described_class.new }

  describe "ATOMIC_BLOCKS" do
    it "lists the five SIP CJK extension blocks that cannot be sub-split" do
      expect(described_class::ATOMIC_BLOCKS).to eq(
        "CJK_Ext_B" => 0x2A700..0x2B73F,
        "CJK_Ext_C" => 0x2B740..0x2B81F,
        "CJK_Ext_D" => 0x2B820..0x2CEAF,
        "CJK_Ext_E" => 0x2CEB0..0x2EBEF,
        "CJK_Ext_F" => 0x2EBF0..0x2EE5F,
      )
    end

    it "is frozen" do
      expect(described_class::ATOMIC_BLOCKS).to be_frozen
    end
  end

  describe "CARVE_OUT_BLOCKS" do
    it "lists BMP-resident blocks that get their own bucket when BMP overflows" do
      expect(described_class::CARVE_OUT_BLOCKS).to eq(
        "CJK_Unified_Ideographs" => 0x4E00..0x9FFF,
        "Hangul_Syllables" => 0xAC00..0xD7AF,
      )
    end

    it "is frozen" do
      expect(described_class::CARVE_OUT_BLOCKS).to be_frozen
    end
  end

  describe "RECOGNIZED_BLOCKS" do
    it "is the union of ATOMIC_BLOCKS and CARVE_OUT_BLOCKS" do
      union = described_class::ATOMIC_BLOCKS.merge(described_class::CARVE_OUT_BLOCKS)
      expect(described_class::RECOGNIZED_BLOCKS).to eq(union)
    end

    it "contains every codepoint range used for sub-splitting" do
      # Spot-check one atomic and one carve-out entry
      expect(described_class::RECOGNIZED_BLOCKS).to include(
        "CJK_Ext_B" => 0x2A700..0x2B73F,
        "CJK_Unified_Ideographs" => 0x4E00..0x9FFF,
        "Hangul_Syllables" => 0xAC00..0xD7AF,
      )
    end
  end

  describe "#call" do
    it "returns a Blueprint with no partitions for an empty cp_map" do
      blueprint = partitioner.call({})
      expect(blueprint).to be_a(Fontisan::Stitcher::PartitionStrategy::Blueprint)
      expect(blueprint.partitions).to eq([])
    end

    it "groups all BMP codepoints into one :plane_0 partition when under cap" do
      cp_map = { 0x41 => :latin, 0x4E00 => :cjk }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to eq([:plane_0])
      expect(blueprint.partitions.first.cps).to contain_exactly(0x41, 0x4E00)
    end

    it "emits separate partitions per plane when codepoints span planes" do
      cp_map = { 0x41 => :latin, 0x20000 => :cjk }
      blueprint = partitioner.call(cp_map)

      expect(blueprint.names).to eq(%i[plane_0 plane_2])
    end

    it "sub-splits a plane that exceeds the cap" do
      # 200 BMP codepoints under cap=100 → multiple :plane_0_X partitions
      cp_map = (0x41..(0x41 + 199)).each_with_index.to_h do |cp, _i|
        [cp, :donor]
      end
      blueprint = partitioner.call(cp_map, cap: 100)

      names = blueprint.names
      expect(names).to all(match(/\Aplane_0_[a-z]+\z/))
      expect(names.size).to be >= 2
    end

    it "raises PartitionCapExceededError when a single atomic block exceeds the cap" do
      # CJK Ext B alone is 0x2A700..0x2B73F (~6592 cps). With cap=100 it
      # cannot be sub-split further.
      cp_map = (0x2A700..0x2A700 + 200).each_with_index.to_h do |cp, _i|
        [cp, :cjk]
      end
      expect do
        partitioner.call(cp_map, cap: 100)
      end.to raise_error(Fontisan::PartitionCapExceededError,
                         /single Unicode block/)
    end

    context "when BMP overflows the cap with CJK + Hangul present" do
      # cap=4, total BMP codepoints=6 → sub-split triggered. Each bucket
      # (other, CJK, Hangul) has exactly 2 codepoints, which fits in cap=4,
      # so each bucket becomes one partition. The test verifies that the
      # carve-out boundaries actually separate the buckets.
      let(:cap) { 4 }

      let(:cp_map) do
        {
          0x41 => :latin, 0x42 => :latin,           # ASCII → :other
          0x4E00 => :cjk, 0x4E01 => :cjk,           # CJK Unified Ideographs
          0xAC00 => :hangul, 0xAC01 => :hangul # Hangul Syllables
        }
      end

      it "emits three sub-split partitions (other, CJK, Hangul)" do
        blueprint = partitioner.call(cp_map, cap: cap)
        expect(blueprint.names).to eq(%i[plane_0_a plane_0_b plane_0_c])
      end

      it "keeps ASCII codepoints in the first partition" do
        blueprint = partitioner.call(cp_map, cap: cap)
        first_cps = blueprint.partitions.first.cps
        expect(first_cps).to contain_exactly(0x41, 0x42)
      end

      it "keeps CJK Unified Ideographs in their own partition" do
        blueprint = partitioner.call(cp_map, cap: cap)
        cjk_partition = blueprint.partitions.find { |p| p.cps.include?(0x4E00) }
        expect(cjk_partition.cps).to contain_exactly(0x4E00, 0x4E01)
      end

      it "keeps Hangul Syllables in their own partition" do
        blueprint = partitioner.call(cp_map, cap: cap)
        hangul_partition = blueprint.partitions.find do |p|
          p.cps.include?(0xAC00)
        end
        expect(hangul_partition.cps).to contain_exactly(0xAC00, 0xAC01)
      end
    end

    context "when a carve-out block alone exceeds the cap" do
      it "chunks the carve-out block instead of raising" do
        # Hangul Syllables with cap=2 → carve-out gets chunked, no raise.
        # (An atomic block under the same conditions would raise.)
        cp_map = { 0xAC00 => :hangul, 0xAC01 => :hangul, 0xAC02 => :hangul }
        blueprint = partitioner.call(cp_map, cap: 2)

        expect(blueprint.names).to eq(%i[plane_0_a plane_0_b])
        all_cps = blueprint.partitions.flat_map(&:cps)
        expect(all_cps).to contain_exactly(0xAC00, 0xAC01, 0xAC02)
      end
    end
  end

  describe "Partition#apply_to" do
    let(:ufo) { Fontisan::Ufo }

    def make_font_with(name, cp)
      font = ufo::Font.new
      font.info.units_per_em = 1000
      font.glyphs[".notdef"] = ufo::Glyph.new(name: ".notdef")

      g = ufo::Glyph.new(name: name)
      g.width = 500
      g.add_unicode(cp)
      g.add_contour(ufo::Contour.new([
                                       ufo::Point.new(x: 0, y: 0, type: "line"),
                                       ufo::Point.new(x: 100, y: 0,
                                                      type: "line"),
                                       ufo::Point.new(x: 100, y: 100,
                                                      type: "line"),
                                     ]))
      font.glyphs[name] = g
      font
    end

    it "pushes bindings into the Stitcher via include_codepoints_map" do
      cp_map = { 0x41 => :latin, 0x4E00 => :cjk }
      blueprint = partitioner.call(cp_map)

      donor_latin = make_font_with("A", 0x41)
      donor_cjk   = make_font_with("uni4E00", 0x4E00)

      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(:latin, donor_latin)
      stitcher.add_source(:cjk, donor_cjk)

      declared = blueprint.apply_to(stitcher)
      expect(declared).to eq([:plane_0])
      expect(stitcher.subfonts[:plane_0]).not_to be_empty
    end
  end
end
