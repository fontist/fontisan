# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "cbdt_fixture"

# Self-test for the CbdtFixture helper. Verifies that the built font
# parses through every BinData model the rest of the codebase uses, so
# any layout drift in either the fixture or the models surfaces here
# rather than silently corrupting downstream specs.
RSpec.describe Fontisan::SpecHelpers::CbdtFixture do
  let(:codepoints) { [0x1F600, 0x1F601, 0x1F600 + 0x10] }
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "cbdt.ttf") }
  let(:font) do
    described_class.write_font(codepoints: codepoints, path: path)
    Fontisan::FontLoader.load(path, font_index: 0, mode: :full, lazy: false)
  end

  it "produces a loadable TrueType font" do
    expect(font).to be_a(Fontisan::TrueTypeFont)
  end

  it "includes the required minimal table set" do
    expected = %w[CBDT CBLC OS/2 cmap head hhea hmtx maxp name post]
    expect(font.table_data.keys.sort).to eq(expected)
  end

  it "does not include outline tables (so Source#bitmap_mode is :cbdt)" do
    expect(font.table_data).not_to include("glyf", "loca", "CFF ", "CFF2")
  end

  describe "CBLC" do
    let(:cblc) { Fontisan::Tables::Cblc.read(font.table_data["CBLC"]) }

    it "is a valid v3.0 table" do
      expect(Integer(cblc.version)).to eq(0x00030000)
      expect(cblc).to be_valid
    end

    it "exposes one strike at the configured ppem/bit depth" do
      expect(cblc.bitmap_sizes.length).to eq(1)
      strike = cblc.bitmap_sizes[0]
      expect(strike.ppem).to eq(16)
      expect(strike.bit_depth).to eq(32)
      expect(strike.start_glyph_index).to eq(1)
      expect(strike.end_glyph_index).to eq(codepoints.size)
    end

    it "yields one glyph location per placeholder glyph" do
      locations = cblc.each_glyph_location.to_a
      expect(locations.length).to eq(codepoints.size)
      expect(locations.map(&:glyph_id)).to eq((1..codepoints.size).to_a)
      expect(locations.map(&:byte_length).uniq).to eq([6])
    end
  end

  describe "CBDT" do
    let(:cbdt) { Fontisan::Tables::Cbdt.read(font.table_data["CBDT"]) }
    let(:cblc) { Fontisan::Tables::Cblc.read(font.table_data["CBLC"]) }

    it "is a valid v3.0 table" do
      expect(cbdt.version).to eq(0x00030000)
      expect(cbdt).to be_valid
    end

    it "exposes a bitmap block decodable at every CBLC-located offset" do
      cblc.each_glyph_location do |loc|
        block = cbdt.bitmap_data_at(loc.cbdt_offset, loc.byte_length)
        expect(block).not_to be_nil,
                             "gid #{loc.glyph_id} offset #{loc.cbdt_offset} undecodable"
        expect(block.bytesize).to eq(loc.byte_length)
      end
    end
  end

  describe "cmap" do
    it "maps every fixture codepoint to a placeholder glyph" do
      mappings = font.table("cmap").unicode_mappings
      codepoints.each_with_index do |cp, i|
        expect(mappings).to include(cp => i + 1),
                            "codepoint U+#{cp.to_s(16)} missing from cmap"
      end
    end
  end
end
