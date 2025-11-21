# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_writer"
require "fontisan/constants"

RSpec.describe Fontisan::FontWriter do
  describe ".write_font" do
    let(:minimal_tables) do
      {
        "head" => create_head_table,
        "maxp" => create_maxp_table,
        "hhea" => create_hhea_table,
      }
    end

    it "returns a binary string" do
      result = described_class.write_font(minimal_tables)

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "writes correct sfnt version for TrueType" do
      result = described_class.write_font(minimal_tables)

      # First 4 bytes should be sfnt version (0x00010000)
      version = result[0, 4].unpack1("N")
      expect(version).to eq(0x00010000)
    end

    it "writes correct sfnt version for OpenType/CFF" do
      cff_tables = minimal_tables.merge("CFF " => "CFF data")
      result = described_class.write_font(cff_tables)

      # First 4 bytes should be 'OTTO' (0x4F54544F)
      version = result[0, 4].unpack1("N")
      expect(version).to eq(0x4F54544F)
    end

    it "writes correct number of tables" do
      result = described_class.write_font(minimal_tables)

      # Bytes 4-5 contain number of tables
      num_tables = result[4, 2].unpack1("n")
      expect(num_tables).to eq(3)
    end

    it "calculates search range correctly" do
      result = described_class.write_font(minimal_tables)

      # For 3 tables: max power of 2 <= 3 is 2, so searchRange = 2 * 16 = 32
      search_range = result[6, 2].unpack1("n")
      expect(search_range).to eq(32)
    end

    it "calculates entry selector correctly" do
      result = described_class.write_font(minimal_tables)

      # For 3 tables: log2(2) = 1
      entry_selector = result[8, 2].unpack1("n")
      expect(entry_selector).to eq(1)
    end

    it "calculates range shift correctly" do
      result = described_class.write_font(minimal_tables)

      # rangeShift = (3 * 16) - 32 = 16
      range_shift = result[10, 2].unpack1("n")
      expect(range_shift).to eq(16)
    end

    it "writes table directory entries" do
      result = described_class.write_font(minimal_tables)

      # Skip offset table (12 bytes)
      offset = 12

      # Check first table entry (16 bytes each)
      tag = result[offset, 4]
      expect(tag).to match(/head|hhea|maxp/)

      # Verify table entry structure
      checksum = result[offset + 4, 4].unpack1("N")
      table_offset = result[offset + 8, 4].unpack1("N")
      length = result[offset + 12, 4].unpack1("N")

      expect(checksum).to be > 0
      expect(table_offset).to be >= 12 + (3 * 16) # After directory
      expect(length).to be > 0
    end

    it "pads table data to 4-byte boundaries" do
      # Create a table with non-4-byte-aligned length
      tables = {
        "head" => "A" * 53, # Not divisible by 4
        "maxp" => "B" * 32, # Divisible by 4
      }

      result = described_class.write_font(tables)

      # Find table offsets from directory
      head_offset = result[12 + 8, 4].unpack1("N")
      maxp_offset = result[12 + 16 + 8, 4].unpack1("N")

      # Check that tables start at offsets that reflect proper padding
      # maxp should start after head + padding
      expected_maxp_offset = head_offset + 53 + 3 # 3 bytes padding
      expect(maxp_offset).to eq(expected_maxp_offset)
    end

    it "orders tables according to recommended order" do
      tables = {
        "post" => "post data",
        "head" => create_head_table,
        "hhea" => create_hhea_table,
        "maxp" => create_maxp_table,
        "cmap" => "cmap data",
      }

      result = described_class.write_font(tables)

      # Extract table tags from directory
      tags = []
      5.times do |i|
        offset = 12 + (i * 16)
        tags << result[offset, 4]
      end

      # head should come before hhea, hhea before maxp, etc.
      expect(tags.index("head")).to be < tags.index("hhea")
      expect(tags.index("hhea")).to be < tags.index("maxp")
      expect(tags.index("maxp")).to be < tags.index("cmap")
    end

    it "updates head table checksum adjustment" do
      tables = {
        "head" => create_head_table_with_zero_checksum,
        "maxp" => create_maxp_table,
      }

      result = described_class.write_font(tables)

      # Find head table offset
      head_offset = result[12 + 8, 4].unpack1("N")

      # Check that checksumAdjustment (at offset 8 in head) is non-zero
      checksum_adjustment = result[head_offset + 8, 4].unpack1("N")
      expect(checksum_adjustment).not_to eq(0)

      # Verify the entire font checksum equals the magic number
      font_checksum = calculate_font_checksum(result)
      expect(font_checksum).to eq(Fontisan::Constants::CHECKSUM_ADJUSTMENT_MAGIC)
    end

    context "with custom sfnt version" do
      it "uses provided sfnt version" do
        result = described_class.write_font(
          minimal_tables,
          sfnt_version: 0x74727565, # 'true'
        )

        version = result[0, 4].unpack1("N")
        expect(version).to eq(0x74727565)
      end
    end

    context "with multiple tables" do
      let(:many_tables) do
        {
          "head" => create_head_table,
          "hhea" => create_hhea_table,
          "maxp" => create_maxp_table,
          "hmtx" => "hmtx data",
          "cmap" => "cmap data",
          "name" => "name data",
          "post" => "post data",
          "OS/2" => "OS/2 data",
        }
      end

      it "handles many tables correctly" do
        result = described_class.write_font(many_tables)

        num_tables = result[4, 2].unpack1("n")
        expect(num_tables).to eq(8)

        # Verify all table tags are present
        tags = []
        8.times do |i|
          offset = 12 + (i * 16)
          tags << result[offset, 4]
        end

        many_tables.each_key do |tag|
          expect(tags).to include(tag)
        end
      end
    end
  end

  describe ".write_to_file" do
    let(:tables) do
      {
        "head" => create_head_table,
        "maxp" => create_maxp_table,
      }
    end

    it "writes font to file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.ttf")
        bytes_written = described_class.write_to_file(tables, path)

        expect(File.exist?(path)).to be true
        expect(bytes_written).to be > 0
        expect(File.size(path)).to eq(bytes_written)
      end
    end

    it "creates parent directories if needed" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "subdir", "test.ttf")
        described_class.write_to_file(tables, path)

        expect(File.exist?(path)).to be true
      end
    end
  end

  describe "#write" do
    let(:writer) do
      described_class.new(
        { "head" => create_head_table, "maxp" => create_maxp_table },
        sfnt_version: 0x00010000,
      )
    end

    it "returns a binary string" do
      result = writer.write

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "includes offset table" do
      result = writer.write

      # First 12 bytes are offset table
      expect(result.bytesize).to be >= 12
    end

    it "includes table directory" do
      result = writer.write

      # Should have directory entries (16 bytes each)
      expect(result.bytesize).to be >= 12 + (2 * 16)
    end

    it "includes table data" do
      result = writer.write

      # Should have offset table + directory + table data
      min_size = 12 + (2 * 16) + create_head_table.bytesize +
        create_maxp_table.bytesize
      expect(result.bytesize).to be >= min_size
    end
  end

  # Helper methods

  def create_head_table
    # Create a minimal head table (54 bytes)
    data = String.new(encoding: Encoding::BINARY)
    data << [0x00010000].pack("N")  # version
    data << [0x00010000].pack("N")  # fontRevision
    data << [0].pack("N")           # checksumAdjustment (will be updated)
    data << [0x5F0F3CF5].pack("N")  # magicNumber
    data << [0].pack("n")           # flags
    data << [2048].pack("n")        # unitsPerEm
    data << [0, 0].pack("Q>")       # created
    data << [0, 0].pack("Q>")       # modified
    data << [0].pack("n")           # xMin
    data << [0].pack("n")           # yMin
    data << [1000].pack("n")        # xMax
    data << [1000].pack("n")        # yMax
    data << [0].pack("n")           # macStyle
    data << [8].pack("n")           # lowestRecPPEM
    data << [0].pack("n")           # fontDirectionHint
    data << [0].pack("n")           # indexToLocFormat
    data << [0].pack("n")           # glyphDataFormat
    data
  end

  def create_head_table_with_zero_checksum
    # Same as create_head_table but ensures checksumAdjustment is 0
    data = create_head_table
    data[8, 4] = [0].pack("N")
    data
  end

  def create_maxp_table
    # Create a minimal maxp table (version 0.5, 6 bytes)
    data = String.new(encoding: Encoding::BINARY)
    data << [0x00005000].pack("N")  # version 0.5
    data << [100].pack("n")         # numGlyphs
    data
  end

  def create_hhea_table
    # Create a minimal hhea table (36 bytes)
    data = String.new(encoding: Encoding::BINARY)
    data << [0x00010000].pack("N")  # version
    data << [2048].pack("n")        # ascent
    data << [-512].pack("n")        # descent
    data << [0].pack("n")           # lineGap
    data << [1000].pack("n")        # advanceWidthMax
    data << [0].pack("n")           # minLeftSideBearing
    data << [0].pack("n")           # minRightSideBearing
    data << [1000].pack("n")        # xMaxExtent
    data << [1].pack("n")           # caretSlopeRise
    data << [0].pack("n")           # caretSlopeRun
    data << [0].pack("n")           # caretOffset
    data << [0, 0, 0, 0].pack("n4") # reserved
    data << [0].pack("n")           # metricDataFormat
    data << [100].pack("n")         # numOfLongHorMetrics
    data
  end

  def calculate_font_checksum(data)
    # Pad to 4-byte boundary
    padded = data.dup
    padding = (4 - (data.bytesize % 4)) % 4
    padded << ("\0" * padding) if padding > 0

    # Sum all uint32 values
    sum = 0
    (0...padded.bytesize).step(4) do |i|
      value = padded[i, 4].unpack1("N")
      sum = (sum + value) & 0xFFFFFFFF
    end

    sum
  end
end
