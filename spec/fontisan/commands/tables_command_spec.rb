# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::TablesCommand do
  # Helper to build font with tables
  def build_font_data(sfnt_version: 0x00010000, tables_data: {})
    sfnt_bytes = [sfnt_version].pack("N")
    num_tables = [tables_data.size].pack("n")
    search_range = [0].pack("n")
    entry_selector = [0].pack("n")
    range_shift = [0].pack("n")

    directory = sfnt_bytes + num_tables + search_range + entry_selector + range_shift

    offset = 12 + (tables_data.size * 16)
    table_entries = ""
    table_data = ""

    tables_data.each do |tag, data|
      tag_bytes = tag.ljust(4, " ")
      checksum = [12_345].pack("N")
      offset_bytes = [offset].pack("N")
      length = [data.bytesize].pack("N")

      table_entries += tag_bytes + checksum + offset_bytes + length
      table_data += data

      offset += data.bytesize
    end

    directory + table_entries + table_data
  end

  let(:font_data) do
    build_font_data(
      tables_data: {
        "head" => ("\x00" * 54),
        "name" => ("\x00" * 100),
        "OS/2" => ("\x00" * 96),
      },
    )
  end

  let(:temp_font_file) do
    file = Tempfile.new(["test-font", ".ttf"])
    file.binmode
    file.write(font_data)
    file.close
    file
  end

  let(:command) { described_class.new(temp_font_file.path) }

  after do
    temp_font_file&.unlink
  end

  describe "#run" do
    it "returns a TableInfo instance" do
      table_info = command.run
      expect(table_info).to be_a(Fontisan::Models::TableInfo)
    end

    it "extracts sfnt_version" do
      table_info = command.run
      expect(table_info.sfnt_version).to eq("TrueType (0x00010000)")
    end

    it "extracts num_tables" do
      table_info = command.run
      expect(table_info.num_tables).to eq(3)
    end

    it "extracts all tables" do
      table_info = command.run
      expect(table_info.tables).to be_an(Array)
      expect(table_info.tables.length).to eq(3)
    end

    it "creates TableEntry objects" do
      table_info = command.run
      expect(table_info.tables).to all(be_a(Fontisan::Models::TableEntry))
    end

    it "includes all table metadata" do
      table_info = command.run
      table_info.tables.each do |table|
        expect(table.tag).to be_a(String)
        expect(table.tag.length).to eq(4)
        expect(table.length).to be_a(Integer)
        expect(table.offset).to be_a(Integer)
        expect(table.checksum).to be_a(Integer)
      end
    end

    it "lists correct table tags" do
      table_info = command.run
      tags = table_info.tables.map(&:tag)
      expect(tags).to contain_exactly("head", "name", "OS/2")
    end

    context "with OpenType CFF fonts" do
      let(:font_data) do
        build_font_data(
          sfnt_version: 0x4F54544F,
          tables_data: { "CFF " => ("\x00" * 100) },
        )
      end

      it "formats sfnt_version correctly" do
        table_info = command.run
        expect(table_info.sfnt_version).to eq("OpenType CFF (OTTO)")
      end
    end

    context "with unknown SFNT version" do
      let(:font_data) do
        build_font_data(
          sfnt_version: 0x12345678,
          tables_data: { "test" => ("\x00" * 10) },
        )
      end

      it "raises InvalidFontError for unknown SFNT version" do
        expect do
          described_class.new(temp_font_file.path)
        end.to raise_error(Fontisan::InvalidFontError, /Unknown font format/)
      end
    end
  end

  describe "#format_sfnt_version" do
    it "formats TrueType version" do
      expect(command.send(:format_sfnt_version,
                          0x00010000)).to eq("TrueType (0x00010000)")
    end

    it "formats OpenType CFF version" do
      expect(command.send(:format_sfnt_version,
                          0x4F54544F)).to eq("OpenType CFF (OTTO)")
    end

    it "formats custom version" do
      expect(command.send(:format_sfnt_version, 0xABCDEF01)).to eq("0xABCDEF01")
    end

    it "formats zero version" do
      expect(command.send(:format_sfnt_version, 0)).to eq("0x00000000")
    end
  end
end
