# frozen_string_literal: true

require "spec_helper"
require "fontisan/ucd/index_builder"
require "fontisan/models/ucd"

RSpec.describe Fontisan::Ucd::IndexBuilder do
  describe ".build_from_ucd" do
    let(:xml) do
      <<~XML
        <ucd>
          <char cp="0041" name="LATIN CAPITAL LETTER A" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
          <char cp="0042" name="LATIN CAPITAL LETTER B" general-category="Lu" script="Latin" block="Basic Latin" age="1.1"/>
          <char cp="0061" name="LATIN SMALL LETTER A" general-category="Ll" script="Latin" block="Basic Latin" age="1.1"/>
          <char first-cp="0080" last-cp="00FF" name="LATIN-1 SUPPLEMENT RANGE" general-category="So" script="Latin" block="Latin-1 Supplement" age="1.1"/>
          <char cp="0391" name="GREEK CAPITAL LETTER ALPHA" general-category="Lu" script="Greek" block="Greek and Coptic" age="1.1"/>
        </ucd>
      XML
    end

    let(:ucd) { Fontisan::Models::Ucd::Ucd.from_xml(xml) }

    it "returns two indices (blocks, scripts)" do
      blocks, scripts = described_class.build_from_ucd(ucd)
      expect(blocks).to be_a(Fontisan::Ucd::Index)
      expect(scripts).to be_a(Fontisan::Ucd::Index)
    end

    it "groups codepoints by block name" do
      blocks, = described_class.build_from_ucd(ucd)
      expect(blocks.lookup(0x0041)).to eq("Basic Latin")
      expect(blocks.lookup(0x0080)).to eq("Latin-1 Supplement")
      expect(blocks.lookup(0x00FF)).to eq("Latin-1 Supplement")
    end

    it "coalesces adjacent single codepoints into ranges" do
      blocks, = described_class.build_from_ucd(ucd)
      # Basic Latin has 0x41, 0x42, 0x61 — should be 2 disjoint ranges after coalescing:
      # 0x41-0x42 and 0x61-0x61
      basic_latin_ranges = blocks.entries.select { |e| e.name == "Basic Latin" }
      expect(basic_latin_ranges.length).to eq(2)
      expect(basic_latin_ranges.map(&:first_cp)).to contain_exactly(0x41, 0x61)
    end

    it "groups codepoints by script" do
      _, scripts = described_class.build_from_ucd(ucd)
      expect(scripts.lookup(0x0041)).to eq("Latin")
      expect(scripts.lookup(0x0391)).to eq("Greek")
    end

    it "uses range entries for char elements with first-cp/last-cp" do
      blocks, = described_class.build_from_ucd(ucd)
      # The 0x80-0xFF range should produce exactly one RangeEntry
      latin1_ranges = blocks.entries.select { |e| e.name == "Latin-1 Supplement" }
      expect(latin1_ranges.length).to eq(1)
      expect(latin1_ranges.first.first_cp).to eq(0x80)
      expect(latin1_ranges.first.last_cp).to eq(0xFF)
    end
  end
end
