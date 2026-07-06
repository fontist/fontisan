# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::SfntBuilder do
  describe ".build" do
    let(:flavor) { Fontisan::Constants::SFNT_VERSION_TRUETYPE }

    it "returns a binary string" do
      bytes = described_class.build(flavor:, tables: { "head" => "\x00" * 54 })
      expect(bytes).to be_a(String)
      expect(bytes.encoding).to eq(Encoding::BINARY)
    end

    it "starts with the SFNT flavor" do
      bytes = described_class.build(flavor:, tables: { "head" => "\x00" * 54 })
      expect(bytes[0, 4].unpack1("N")).to eq(flavor)
    end

    it "writes a 12-byte offset table + 16-byte directory per table + padded data" do
      tables = { "head" => "\x00" * 54, "maxp" => "\x00" * 32 }
      bytes = described_class.build(flavor:, tables:)

      # numTables field
      num_tables = bytes[4, 2].unpack1("n")
      expect(num_tables).to eq(2)

      # First table directory entry at offset 12 (alphabetical: head before maxp)
      # SFNT TableDirectoryEntry: tag(4) checksum(4) offset(4) length(4) = 16 bytes
      tag = bytes[12, 4]
      checksum = bytes[16, 4].unpack1("N")
      offset = bytes[20, 4].unpack1("N")
      length = bytes[24, 4].unpack1("N")
      expect(tag).to eq("head")
      expect(length).to eq(54)
      expect(checksum).to be_an(Integer)
      expect(offset).to eq(12 + (2 * 16)) # after offset table + directory
    end

    it "pads table data to 4-byte boundary" do
      # head table is 54 bytes (not 4-aligned). Padding = 2 bytes.
      bytes = described_class.build(flavor:, tables: { "head" => "\x00" * 54 })
      # Head entry is first (alphabetically). Find its data start (12 + 16 = 28).
      # Then 54 bytes + 2 padding = 56 bytes total before EOF.
      expect(bytes.bytesize).to eq(12 + 16 + 54 + 2) # offset + dir + data + padding
    end
  end
end
