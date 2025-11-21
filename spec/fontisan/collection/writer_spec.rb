# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Collection::Writer do
  let(:font1_header) do
    double("header", sfnt_version: 0x00010000)
  end

  let(:font2_header) do
    double("header", sfnt_version: 0x00010000)
  end

  let(:font1) do
    double(
      "truetype_font",
      table_names: %w[head hhea],
      header: font1_header,
    )
  end

  let(:font2) do
    double(
      "truetype_font",
      table_names: %w[head hhea],
      header: font2_header,
    )
  end

  let(:fonts) { [font1, font2] }

  let(:sharing_map) do
    {
      0 => {
        "head" => { canonical_id: "head_1", data: "HEAD1" * 10, size: 50,
                    shared: false },
        "hhea" => { canonical_id: "hhea_shared", data: "HHEA" * 9, size: 36,
                    shared: true },
      },
      1 => {
        "head" => { canonical_id: "head_2", data: "HEAD2" * 10, size: 50,
                    shared: false },
        "hhea" => { canonical_id: "hhea_shared", data: "HHEA" * 9, size: 36,
                    shared: true },
      },
    }
  end

  let(:offsets) do
    {
      header_offset: 0,
      offset_table_offset: 12,
      font_directory_offsets: [20, 80],
      table_offsets: {
        "head_1" => 200,
        "head_2" => 260,
        "hhea_shared" => 320,
      },
      font_table_directories: {
        0 => { offset: 20, size: 60, num_tables: 2 },
        1 => { offset: 80, size: 60, num_tables: 2 },
      },
    }
  end

  describe "#initialize" do
    it "initializes with required parameters" do
      writer = described_class.new(fonts, sharing_map, offsets)
      expect(writer).to be_a(described_class)
    end

    it "accepts format parameter" do
      writer = described_class.new(fonts, sharing_map, offsets, format: :otc)
      expect(writer).to be_a(described_class)
    end

    it "raises error when fonts is nil" do
      expect do
        described_class.new(nil, sharing_map, offsets)
      end.to raise_error(ArgumentError, "fonts cannot be nil or empty")
    end

    it "raises error when sharing_map is nil" do
      expect do
        described_class.new(fonts, nil, offsets)
      end.to raise_error(ArgumentError, "sharing_map cannot be nil")
    end

    it "raises error when offsets is nil" do
      expect do
        described_class.new(fonts, sharing_map, nil)
      end.to raise_error(ArgumentError, "offsets cannot be nil")
    end

    it "raises error for invalid format" do
      expect do
        described_class.new(fonts, sharing_map, offsets, format: :invalid)
      end.to raise_error(ArgumentError, "format must be :ttc or :otc")
    end
  end

  describe "#write_collection" do
    let(:writer) { described_class.new(fonts, sharing_map, offsets) }

    it "returns binary string" do
      binary = writer.write_collection
      expect(binary).to be_a(String)
      expect(binary.encoding).to eq(Encoding::BINARY)
    end

    it "creates non-empty binary" do
      binary = writer.write_collection
      expect(binary.bytesize).to be > 0
    end

    it "starts with TTC signature" do
      binary = writer.write_collection
      signature = binary[0, 4]
      expect(signature).to eq("ttcf")
    end

    it "includes version information" do
      binary = writer.write_collection
      major_version = binary[4, 2].unpack1("n")
      minor_version = binary[6, 2].unpack1("n")
      expect(major_version).to eq(1)
      expect(minor_version).to eq(0)
    end

    it "includes number of fonts" do
      binary = writer.write_collection
      num_fonts = binary[8, 4].unpack1("N")
      expect(num_fonts).to eq(2)
    end
  end

  describe "#write_to_file" do
    let(:writer) { described_class.new(fonts, sharing_map, offsets) }
    let(:temp_file) { Tempfile.new(["test_collection", ".ttc"]) }

    after do
      temp_file.close
      temp_file.unlink
    end

    it "writes to file" do
      bytes_written = writer.write_to_file(temp_file.path)
      expect(bytes_written).to be > 0
      expect(File.exist?(temp_file.path)).to be true
    end

    it "creates readable TTC file" do
      writer.write_to_file(temp_file.path)
      content = File.binread(temp_file.path)
      expect(content[0, 4]).to eq("ttcf")
    end
  end

  context "with TTC format" do
    let(:writer) do
      described_class.new(fonts, sharing_map, offsets, format: :ttc)
    end

    it "creates TTC with correct signature" do
      binary = writer.write_collection
      expect(binary[0, 4]).to eq("ttcf")
    end
  end

  context "with OTC format" do
    let(:writer) do
      described_class.new(fonts, sharing_map, offsets, format: :otc)
    end

    it "creates OTC with correct signature" do
      binary = writer.write_collection
      expect(binary[0, 4]).to eq("ttcf")
    end
  end

  describe "binary structure" do
    let(:writer) { described_class.new(fonts, sharing_map, offsets) }

    it "has correct header size" do
      binary = writer.write_collection
      # Header: 4 (tag) + 2 (major) + 2 (minor) + 4 (num_fonts) = 12 bytes
      expect(binary.bytesize).to be >= 12
    end

    it "includes offset table after header" do
      binary = writer.write_collection
      # Offset table starts at byte 12
      offset1 = binary[12, 4].unpack1("N")
      offset2 = binary[16, 4].unpack1("N")
      expect(offset1).to be > 0
      expect(offset2).to be > offset1
    end
  end
end
