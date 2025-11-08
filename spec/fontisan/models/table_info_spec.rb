# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/table_info"

RSpec.describe Fontisan::Models::TableEntry do
  describe "initialization" do
    it "creates a table entry with all attributes" do
      entry = described_class.new(
        tag: "head",
        length: 54,
        offset: 1024,
        checksum: 0x12345678,
      )

      expect(entry.tag).to eq("head")
      expect(entry.length).to eq(54)
      expect(entry.offset).to eq(1024)
      expect(entry.checksum).to eq(0x12345678)
    end

    it "creates a table entry with nil values" do
      entry = described_class.new

      expect(entry.tag).to be_nil
      expect(entry.length).to be_nil
      expect(entry.offset).to be_nil
      expect(entry.checksum).to be_nil
    end
  end

  describe "YAML serialization" do
    let(:entry) do
      described_class.new(
        tag: "name",
        length: 1024,
        offset: 2048,
        checksum: 0xABCDEF00,
      )
    end

    it "serializes to YAML" do
      yaml = entry.to_yaml

      expect(yaml).to include("tag: name")
      expect(yaml).to include("length: 1024")
      expect(yaml).to include("offset: 2048")
      expect(yaml).to include("checksum: 2882400000")
    end

    it "deserializes from YAML" do
      yaml = entry.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.tag).to eq("name")
      expect(restored.length).to eq(1024)
      expect(restored.offset).to eq(2048)
      expect(restored.checksum).to eq(0xABCDEF00)
    end

    it "handles YAML round-trip" do
      yaml = entry.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.tag).to eq(entry.tag)
      expect(restored.length).to eq(entry.length)
      expect(restored.offset).to eq(entry.offset)
      expect(restored.checksum).to eq(entry.checksum)
    end
  end

  describe "JSON serialization" do
    let(:entry) do
      described_class.new(
        tag: "OS/2",
        length: 96,
        offset: 4096,
        checksum: 0x11223344,
      )
    end

    it "serializes to JSON" do
      json = entry.to_json

      expect(json).to include('"tag":"OS/2"')
      expect(json).to include('"length":96')
      expect(json).to include('"offset":4096')
      expect(json).to include('"checksum":287454020')
    end

    it "deserializes from JSON" do
      json = entry.to_json
      restored = described_class.from_json(json)

      expect(restored.tag).to eq("OS/2")
      expect(restored.length).to eq(96)
      expect(restored.offset).to eq(4096)
      expect(restored.checksum).to eq(0x11223344)
    end

    it "handles JSON round-trip" do
      json = entry.to_json
      restored = described_class.from_json(json)

      expect(restored.tag).to eq(entry.tag)
      expect(restored.length).to eq(entry.length)
      expect(restored.offset).to eq(entry.offset)
      expect(restored.checksum).to eq(entry.checksum)
    end
  end
end

RSpec.describe Fontisan::Models::TableInfo do
  describe "initialization" do
    it "creates table info with attributes" do
      table_info = described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 3,
      )

      expect(table_info.sfnt_version).to eq("0x00010000")
      expect(table_info.num_tables).to eq(3)
      expect(table_info.tables).to be_nil
    end

    it "creates table info with table entries" do
      entries = [
        Fontisan::Models::TableEntry.new(
          tag: "head",
          length: 54,
          offset: 1024,
          checksum: 0x12345678,
        ),
        Fontisan::Models::TableEntry.new(
          tag: "name",
          length: 1024,
          offset: 2048,
          checksum: 0xABCDEF00,
        ),
      ]

      table_info = described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 2,
        tables: entries,
      )

      expect(table_info.tables.size).to eq(2)
      expect(table_info.tables[0].tag).to eq("head")
      expect(table_info.tables[1].tag).to eq("name")
    end
  end

  describe "YAML serialization" do
    let(:table_info) do
      described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 4,
        tables: [
          Fontisan::Models::TableEntry.new(
            tag: "head",
            length: 54,
            offset: 1024,
            checksum: 0x12345678,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "name",
            length: 1024,
            offset: 2048,
            checksum: 0xABCDEF00,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "OS/2",
            length: 96,
            offset: 3072,
            checksum: 0x11223344,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "post",
            length: 32,
            offset: 3200,
            checksum: 0x55667788,
          ),
        ],
      )
    end

    it "serializes to YAML" do
      yaml = table_info.to_yaml

      expect(yaml).to include("sfnt_version: '0x00010000'")
      expect(yaml).to include("num_tables: 4")
      expect(yaml).to include("tables:")
      expect(yaml).to include("tag: head")
      expect(yaml).to include("tag: name")
      expect(yaml).to include("tag: OS/2")
      expect(yaml).to include("tag: post")
    end

    it "deserializes from YAML" do
      yaml = table_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.sfnt_version).to eq("0x00010000")
      expect(restored.num_tables).to eq(4)
      expect(restored.tables.size).to eq(4)
      expect(restored.tables[0].tag).to eq("head")
      expect(restored.tables[1].tag).to eq("name")
      expect(restored.tables[2].tag).to eq("OS/2")
      expect(restored.tables[3].tag).to eq("post")
    end

    it "handles YAML round-trip with collections" do
      yaml = table_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.sfnt_version).to eq(table_info.sfnt_version)
      expect(restored.num_tables).to eq(table_info.num_tables)
      expect(restored.tables.size).to eq(table_info.tables.size)

      restored.tables.each_with_index do |entry, index|
        original_entry = table_info.tables[index]
        expect(entry.tag).to eq(original_entry.tag)
        expect(entry.length).to eq(original_entry.length)
        expect(entry.offset).to eq(original_entry.offset)
        expect(entry.checksum).to eq(original_entry.checksum)
      end
    end
  end

  describe "JSON serialization" do
    let(:table_info) do
      described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 3,
        tables: [
          Fontisan::Models::TableEntry.new(
            tag: "cmap",
            length: 512,
            offset: 5000,
            checksum: 0xAABBCCDD,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "glyf",
            length: 8192,
            offset: 6000,
            checksum: 0x99887766,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "loca",
            length: 256,
            offset: 14_200,
            checksum: 0x55443322,
          ),
        ],
      )
    end

    it "serializes to JSON" do
      json = table_info.to_json

      expect(json).to include('"sfnt_version":"0x00010000"')
      expect(json).to include('"num_tables":3')
      expect(json).to include('"tables":[')
      expect(json).to include('"tag":"cmap"')
      expect(json).to include('"tag":"glyf"')
      expect(json).to include('"tag":"loca"')
    end

    it "deserializes from JSON" do
      json = table_info.to_json
      restored = described_class.from_json(json)

      expect(restored.sfnt_version).to eq("0x00010000")
      expect(restored.num_tables).to eq(3)
      expect(restored.tables.size).to eq(3)
      expect(restored.tables[0].tag).to eq("cmap")
      expect(restored.tables[1].tag).to eq("glyf")
      expect(restored.tables[2].tag).to eq("loca")
    end

    it "handles JSON round-trip with collections" do
      json = table_info.to_json
      restored = described_class.from_json(json)

      expect(restored.sfnt_version).to eq(table_info.sfnt_version)
      expect(restored.num_tables).to eq(table_info.num_tables)
      expect(restored.tables.size).to eq(table_info.tables.size)

      restored.tables.each_with_index do |entry, index|
        original_entry = table_info.tables[index]
        expect(entry.tag).to eq(original_entry.tag)
        expect(entry.length).to eq(original_entry.length)
        expect(entry.offset).to eq(original_entry.offset)
        expect(entry.checksum).to eq(original_entry.checksum)
      end
    end
  end

  describe "sample table data" do
    it "handles common TrueType tables" do
      table_info = described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 9,
        tables: [
          Fontisan::Models::TableEntry.new(
            tag: "cmap",
            length: 1234,
            offset: 100,
            checksum: 0x01234567,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "glyf",
            length: 50_000,
            offset: 5000,
            checksum: 0x12345678,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "head",
            length: 54,
            offset: 200,
            checksum: 0x23456789,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "hhea",
            length: 36,
            offset: 300,
            checksum: 0x3456789A,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "hmtx",
            length: 2048,
            offset: 400,
            checksum: 0x456789AB,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "loca",
            length: 500,
            offset: 2500,
            checksum: 0x56789ABC,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "maxp",
            length: 32,
            offset: 3000,
            checksum: 0x6789ABCD,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "name",
            length: 4096,
            offset: 3100,
            checksum: 0x789ABCDE,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "post",
            length: 32,
            offset: 7200,
            checksum: 0x89ABCDEF,
          ),
        ],
      )

      yaml = table_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.num_tables).to eq(9)
      expect(restored.tables.map(&:tag)).to eq(
        %w[cmap glyf head hhea hmtx loca maxp name post],
      )
    end

    it "handles OpenType CFF tables" do
      table_info = described_class.new(
        sfnt_version: "OTTO",
        num_tables: 5,
        tables: [
          Fontisan::Models::TableEntry.new(
            tag: "CFF ",
            length: 10_000,
            offset: 1000,
            checksum: 0xAABBCCDD,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "OS/2",
            length: 96,
            offset: 11_100,
            checksum: 0xBBCCDDEE,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "cmap",
            length: 500,
            offset: 11_300,
            checksum: 0xCCDDEEFF,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "head",
            length: 54,
            offset: 12_000,
            checksum: 0xDDEEFF00,
          ),
          Fontisan::Models::TableEntry.new(
            tag: "name",
            length: 2000,
            offset: 12_100,
            checksum: 0xEEFF0011,
          ),
        ],
      )

      json = table_info.to_json
      restored = described_class.from_json(json)

      expect(restored.sfnt_version).to eq("OTTO")
      expect(restored.tables.map(&:tag)).to include("CFF ", "OS/2")
    end

    it "handles empty table list" do
      table_info = described_class.new(
        sfnt_version: "0x00010000",
        num_tables: 0,
        tables: [],
      )

      yaml = table_info.to_yaml
      restored = described_class.from_yaml(yaml)

      expect(restored.num_tables).to eq(0)
      # lutaml-model converts empty arrays to nil during deserialization
      expect(restored.tables).to be_nil
    end
  end
end
