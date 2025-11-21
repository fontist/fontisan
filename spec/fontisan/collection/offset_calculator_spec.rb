# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::OffsetCalculator do
  let(:font1_header) do
    double("header", sfnt_version: 0x00010000)
  end

  let(:font2_header) do
    double("header", sfnt_version: 0x00010000)
  end

  let(:font1) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp],
      header: font1_header,
    )
  end

  let(:font2) do
    double(
      "truetype_font",
      table_names: %w[head hhea maxp name],
      header: font2_header,
    )
  end

  let(:fonts) { [font1, font2] }

  let(:sharing_map) do
    {
      0 => {
        "head" => {
          canonical_id: "head_abc123",
          size: 54,
          shared: false,
          data: "x" * 54,
        },
        "hhea" => {
          canonical_id: "hhea_def456",
          size: 36,
          shared: true,
          data: "y" * 36,
        },
        "maxp" => {
          canonical_id: "maxp_ghi789",
          size: 32,
          shared: false,
          data: "z" * 32,
        },
      },
      1 => {
        "head" => {
          canonical_id: "head_xyz999",
          size: 54,
          shared: false,
          data: "a" * 54,
        },
        "hhea" => {
          canonical_id: "hhea_def456",
          size: 36,
          shared: true,
          data: "y" * 36,
        },
        "maxp" => {
          canonical_id: "maxp_jkl012",
          size: 32,
          shared: false,
          data: "b" * 32,
        },
        "name" => {
          canonical_id: "name_mno345",
          size: 100,
          shared: false,
          data: "c" * 100,
        },
      },
    }
  end

  describe "#initialize" do
    it "initializes with sharing map and fonts" do
      calculator = described_class.new(sharing_map, fonts)
      expect(calculator).to be_a(described_class)
    end

    it "raises error when sharing_map is nil" do
      expect do
        described_class.new(nil, fonts)
      end.to raise_error(ArgumentError, "sharing_map cannot be nil")
    end

    it "raises error when fonts is nil" do
      expect do
        described_class.new(sharing_map, nil)
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when fonts is empty" do
      expect do
        described_class.new(sharing_map, [])
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end
  end

  describe "#calculate" do
    let(:calculator) { described_class.new(sharing_map, fonts) }

    it "returns offset map" do
      offsets = calculator.calculate

      expect(offsets).to be_a(Hash)
      expect(offsets).to have_key(:header_offset)
      expect(offsets).to have_key(:offset_table_offset)
      expect(offsets).to have_key(:font_directory_offsets)
      expect(offsets).to have_key(:table_offsets)
      expect(offsets).to have_key(:font_table_directories)
    end

    it "sets header offset to 0" do
      offsets = calculator.calculate
      expect(offsets[:header_offset]).to eq(0)
    end

    it "sets offset table offset to 12" do
      offsets = calculator.calculate
      expect(offsets[:offset_table_offset]).to eq(12)
    end

    it "calculates font directory offsets" do
      offsets = calculator.calculate

      expect(offsets[:font_directory_offsets]).to be_an(Array)
      expect(offsets[:font_directory_offsets].size).to eq(2)
      expect(offsets[:font_directory_offsets].first).to be > 12
    end

    it "ensures offsets are 4-byte aligned" do
      offsets = calculator.calculate

      offsets[:font_directory_offsets].each do |offset|
        expect(offset % 4).to eq(0)
      end

      offsets[:table_offsets].each_value do |offset|
        expect(offset % 4).to eq(0)
      end
    end

    it "calculates table offsets" do
      offsets = calculator.calculate

      expect(offsets[:table_offsets]).to be_a(Hash)
      expect(offsets[:table_offsets]).not_to be_empty
    end

    it "includes offset for each canonical table" do
      offsets = calculator.calculate

      # Should have offsets for all unique canonical tables
      expect(offsets[:table_offsets]).to have_key("hhea_def456") # shared
      expect(offsets[:table_offsets]).to have_key("head_abc123") # unique
      expect(offsets[:table_offsets]).to have_key("head_xyz999") # unique
    end

    it "stores font directory information" do
      offsets = calculator.calculate

      expect(offsets[:font_table_directories]).to have_key(0)
      expect(offsets[:font_table_directories]).to have_key(1)

      dir0 = offsets[:font_table_directories][0]
      expect(dir0).to have_key(:offset)
      expect(dir0).to have_key(:size)
      expect(dir0).to have_key(:num_tables)
      expect(dir0).to have_key(:table_tags)
    end
  end

  describe "#font_directory_offset" do
    let(:calculator) { described_class.new(sharing_map, fonts) }

    it "returns offset for specific font" do
      offset = calculator.font_directory_offset(0)
      expect(offset).to be_a(Integer)
      expect(offset).to be > 12
    end

    it "returns offset for second font" do
      offset = calculator.font_directory_offset(1)
      expect(offset).to be_a(Integer)
      expect(offset).to be > calculator.font_directory_offset(0)
    end
  end

  describe "#table_offset" do
    let(:calculator) { described_class.new(sharing_map, fonts) }

    it "returns offset for canonical table" do
      calculator.calculate
      offset = calculator.table_offset("hhea_def456")
      expect(offset).to be_a(Integer)
    end

    it "returns nil for non-existent table" do
      calculator.calculate
      offset = calculator.table_offset("nonexistent")
      expect(offset).to be_nil
    end
  end

  describe "offset ordering" do
    let(:calculator) { described_class.new(sharing_map, fonts) }

    it "places header at offset 0" do
      offsets = calculator.calculate
      expect(offsets[:header_offset]).to eq(0)
    end

    it "places offset table after header" do
      offsets = calculator.calculate
      expect(offsets[:offset_table_offset]).to eq(12)
    end

    it "places font directories after offset table" do
      offsets = calculator.calculate
      first_dir_offset = offsets[:font_directory_offsets].first
      expect(first_dir_offset).to be >= (12 + 8) # header + offset table (2 fonts * 4 bytes)
    end

    it "places tables after all directories" do
      offsets = calculator.calculate
      last_dir_offset = offsets[:font_table_directories][1][:offset]
      last_dir_size = offsets[:font_table_directories][1][:size]
      last_dir_end = last_dir_offset + last_dir_size

      offsets[:table_offsets].each_value do |table_offset|
        expect(table_offset).to be >= last_dir_end
      end
    end
  end

  describe "alignment requirements" do
    it "aligns all offsets to 4-byte boundaries" do
      calculator = described_class.new(sharing_map, fonts)
      offsets = calculator.calculate

      # Check font directory offsets
      offsets[:font_directory_offsets].each do |offset|
        expect(offset % 4).to eq(0),
                              "Font directory offset #{offset} not 4-byte aligned"
      end

      # Check table offsets
      offsets[:table_offsets].each do |canonical_id, offset|
        expect(offset % 4).to eq(0),
                              "Table offset for #{canonical_id} (#{offset}) not 4-byte aligned"
      end
    end
  end

  context "with single font" do
    let(:single_font) { [font1] }
    let(:single_sharing_map) do
      sharing_map.select { |k, _v| k == 0 }
    end

    it "calculates offsets correctly" do
      calculator = described_class.new(single_sharing_map, single_font)
      offsets = calculator.calculate

      expect(offsets[:font_directory_offsets].size).to eq(1)
      expect(offsets[:table_offsets]).not_to be_empty
    end
  end

  context "with many fonts" do
    let(:many_fonts) { Array.new(5) { font1 } }
    let(:many_sharing_map) do
      (0..4).to_h do |i|
        [i, sharing_map[0]]
      end
    end

    it "calculates offsets for all fonts" do
      calculator = described_class.new(many_sharing_map, many_fonts)
      offsets = calculator.calculate

      expect(offsets[:font_directory_offsets].size).to eq(5)
      expect(offsets[:font_table_directories].size).to eq(5)
    end
  end
end
