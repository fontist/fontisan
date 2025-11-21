# frozen_string_literal: true

require "spec_helper"
require "fontisan/woff2/header"

RSpec.describe Fontisan::Woff2::Woff2Header do
  describe "structure" do
    it "creates a new header instance" do
      header = described_class.new
      expect(header).to be_a(described_class)
    end

    it "has correct signature constant" do
      expect(described_class::SIGNATURE).to eq(0x774F4632)
    end

    it "returns correct header size" do
      expect(described_class.header_size).to eq(48)
    end
  end

  describe "attributes" do
    let(:header) { described_class.new }

    it "has signature attribute" do
      header.signature = 0x774F4632
      expect(header.signature).to eq(0x774F4632)
    end

    it "has flavor attribute" do
      header.flavor = 0x00010000
      expect(header.flavor).to eq(0x00010000)
    end

    it "has length attribute" do
      header.file_length = 50000
      expect(header.file_length).to eq(50000)
    end

    it "has num_tables attribute" do
      header.num_tables = 12
      expect(header.num_tables).to eq(12)
    end

    it "has reserved attribute" do
      header.reserved = 0
      expect(header.reserved).to eq(0)
    end

    it "has total_sfnt_size attribute" do
      header.total_sfnt_size = 75000
      expect(header.total_sfnt_size).to eq(75000)
    end

    it "has total_compressed_size attribute" do
      header.total_compressed_size = 40000
      expect(header.total_compressed_size).to eq(40000)
    end

    it "has version attributes" do
      header.major_version = 1
      header.minor_version = 0
      expect(header.major_version).to eq(1)
      expect(header.minor_version).to eq(0)
    end

    it "has metadata attributes" do
      header.meta_offset = 1000
      header.meta_length = 500
      header.meta_orig_length = 1500
      expect(header.meta_offset).to eq(1000)
      expect(header.meta_length).to eq(500)
      expect(header.meta_orig_length).to eq(1500)
    end

    it "has private data attributes" do
      header.priv_offset = 2000
      header.priv_length = 300
      expect(header.priv_offset).to eq(2000)
      expect(header.priv_length).to eq(300)
    end
  end

  describe "#valid_signature?" do
    let(:header) { described_class.new }

    it "returns true for valid signature" do
      header.signature = 0x774F4632
      expect(header.valid_signature?).to be true
    end

    it "returns false for invalid signature" do
      header.signature = 0x00000000
      expect(header.valid_signature?).to be false
    end
  end

  describe "#truetype?" do
    let(:header) { described_class.new }

    it "returns true for TrueType flavor 0x00010000" do
      header.flavor = 0x00010000
      expect(header.truetype?).to be true
    end

    it "returns true for TrueType flavor 'true'" do
      header.flavor = 0x74727565
      expect(header.truetype?).to be true
    end

    it "returns false for CFF flavor" do
      header.flavor = 0x4F54544F
      expect(header.truetype?).to be false
    end
  end

  describe "#cff?" do
    let(:header) { described_class.new }

    it "returns true for CFF flavor 'OTTO'" do
      header.flavor = 0x4F54544F
      expect(header.cff?).to be true
    end

    it "returns false for TrueType flavor" do
      header.flavor = 0x00010000
      expect(header.cff?).to be false
    end
  end

  describe "#has_metadata?" do
    let(:header) { described_class.new }

    it "returns true when metadata is present" do
      header.meta_offset = 1000
      header.meta_length = 500
      expect(header.has_metadata?).to be true
    end

    it "returns false when offset is zero" do
      header.meta_offset = 0
      header.meta_length = 500
      expect(header.has_metadata?).to be false
    end

    it "returns false when length is zero" do
      header.meta_offset = 1000
      header.meta_length = 0
      expect(header.has_metadata?).to be false
    end

    it "returns false when both are zero" do
      header.meta_offset = 0
      header.meta_length = 0
      expect(header.has_metadata?).to be false
    end
  end

  describe "#has_private_data?" do
    let(:header) { described_class.new }

    it "returns true when private data is present" do
      header.priv_offset = 2000
      header.priv_length = 300
      expect(header.has_private_data?).to be true
    end

    it "returns false when offset is zero" do
      header.priv_offset = 0
      header.priv_length = 300
      expect(header.has_private_data?).to be false
    end

    it "returns false when length is zero" do
      header.priv_offset = 2000
      header.priv_length = 0
      expect(header.has_private_data?).to be false
    end
  end

  describe "binary serialization" do
    let(:header) do
      h = described_class.new
      h.signature = 0x774F4632
      h.flavor = 0x00010000
      h.file_length = 50000
      h.num_tables = 12
      h.reserved = 0
      h.total_sfnt_size = 75000
      h.total_compressed_size = 40000
      h.major_version = 1
      h.minor_version = 0
      h.meta_offset = 0
      h.meta_length = 0
      h.meta_orig_length = 0
      h.priv_offset = 0
      h.priv_length = 0
      h
    end

    it "serializes to binary" do
      binary = header.to_binary_s
      expect(binary).to be_a(String)
      expect(binary.bytesize).to eq(48)
    end

    it "round-trips correctly" do
      binary = header.to_binary_s
      restored = described_class.read(binary)

      expect(restored.signature).to eq(header.signature)
      expect(restored.flavor).to eq(header.flavor)
      expect(restored.num_tables).to eq(header.num_tables)
      expect(restored.file_length).to eq(header.file_length)
      expect(restored.total_sfnt_size).to eq(header.total_sfnt_size)
      expect(restored.total_compressed_size).to eq(header.total_compressed_size)
    end

    it "has big-endian byte order" do
      binary = header.to_binary_s
      # First 4 bytes should be signature in big-endian
      signature_bytes = binary[0, 4].unpack1("N")
      expect(signature_bytes).to eq(0x774F4632)
    end
  end

  describe "typical use cases" do
    it "creates a TrueType WOFF2 header" do
      header = described_class.new
      header.signature = described_class::SIGNATURE
      header.flavor = 0x00010000
      header.num_tables = 15
      header.reserved = 0
      header.total_sfnt_size = 80000
      header.total_compressed_size = 45000
      header.major_version = 1
      header.minor_version = 0
      header.meta_offset = 0
      header.meta_length = 0
      header.meta_orig_length = 0
      header.priv_offset = 0
      header.priv_length = 0

      expect(header.valid_signature?).to be true
      expect(header.truetype?).to be true
      expect(header.cff?).to be false
      expect(header.has_metadata?).to be false
    end

    it "creates a CFF WOFF2 header" do
      header = described_class.new
      header.signature = described_class::SIGNATURE
      header.flavor = 0x4F54544F
      header.num_tables = 10
      header.total_sfnt_size = 60000
      header.total_compressed_size = 35000
      header.major_version = 1
      header.minor_version = 0

      expect(header.valid_signature?).to be true
      expect(header.truetype?).to be false
      expect(header.cff?).to be true
    end
  end
end
