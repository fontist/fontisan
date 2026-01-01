# frozen_string_literal: true

require "spec_helper"
require "fontisan/woff2/directory"

RSpec.describe Fontisan::Woff2::Directory do
  describe "constants" do
    it "has known tags list" do
      expect(described_class::KNOWN_TAGS).to be_an(Array)
      expect(described_class::KNOWN_TAGS.size).to eq(63)
    end

    it "includes common table tags" do
      expect(described_class::KNOWN_TAGS).to include("cmap", "head", "hhea",
                                                     "hmtx", "glyf", "loca")
    end

    it "has transformation constants" do
      expect(described_class::TRANSFORM_NONE).to eq(3)
      expect(described_class::TRANSFORM_GLYF_LOCA).to eq(0)
      expect(described_class::TRANSFORM_HMTX).to eq(1)
    end

    it "has custom tag index" do
      expect(described_class::CUSTOM_TAG_INDEX).to eq(0x3F)
    end
  end

  describe ".encode_uint_base128" do
    it "encodes small values in 1 byte" do
      encoded = described_class.encode_uint_base128(50)
      expect(encoded.bytesize).to eq(1)
      expect(encoded.unpack1("C")).to eq(50)
    end

    it "encodes 127 in 1 byte" do
      encoded = described_class.encode_uint_base128(127)
      expect(encoded.bytesize).to eq(1)
    end

    it "encodes 128 in 2 bytes" do
      encoded = described_class.encode_uint_base128(128)
      expect(encoded.bytesize).to eq(2)
    end

    it "encodes larger values correctly" do
      test_values = [0, 127, 128, 255, 256, 1000, 16383, 16384, 100_000]

      test_values.each do |value|
        encoded = described_class.encode_uint_base128(value)
        expect(encoded).to be_a(String)
        expect(encoded.bytesize).to be <= 5
      end
    end

    it "round-trips values correctly" do
      test_values = [0, 50, 127, 128, 255, 1000, 10_000, 100_000]

      test_values.each do |value|
        encoded = described_class.encode_uint_base128(value)
        io = StringIO.new(encoded)
        decoded = described_class.decode_uint_base128(io)
        expect(decoded).to eq(value)
      end
    end
  end

  describe ".decode_uint_base128" do
    it "decodes single byte values" do
      io = StringIO.new([50].pack("C"))
      decoded = described_class.decode_uint_base128(io)
      expect(decoded).to eq(50)
    end

    it "decodes multi-byte values" do
      encoded = described_class.encode_uint_base128(1000)
      io = StringIO.new(encoded)
      decoded = described_class.decode_uint_base128(io)
      expect(decoded).to eq(1000)
    end

    it "returns nil on EOF" do
      io = StringIO.new("")
      decoded = described_class.decode_uint_base128(io)
      expect(decoded).to be_nil
    end

    it "raises error for invalid encoding" do
      # Create invalid encoding (more than 5 bytes with continuation bit set)
      invalid = [0x80, 0x80, 0x80, 0x80, 0x80, 0x80].pack("C*")
      io = StringIO.new(invalid)

      expect do
        described_class.decode_uint_base128(io)
      end.to raise_error(Fontisan::Error, /Invalid UIntBase128/)
    end
  end

  describe ".encode_255_uint16" do
    it "encodes small values in 1 byte" do
      encoded = described_class.encode_255_uint16(100)
      expect(encoded.bytesize).to eq(1)
      expect(encoded.unpack1("C")).to eq(100)
    end

    it "encodes 252 in 1 byte" do
      encoded = described_class.encode_255_uint16(252)
      expect(encoded.bytesize).to eq(1)
    end

    it "encodes 253 in 2 bytes" do
      encoded = described_class.encode_255_uint16(253)
      expect(encoded.bytesize).to eq(2)
      expect(encoded.unpack("C*")).to eq([253, 0])
    end

    it "encodes values 253-505 in 2 bytes" do
      encoded = described_class.encode_255_uint16(300)
      expect(encoded.bytesize).to eq(2)
    end

    it "encodes large values in 3 bytes" do
      encoded = described_class.encode_255_uint16(1000)
      expect(encoded.bytesize).to eq(3)
    end

    it "round-trips values correctly" do
      test_values = [0, 100, 252, 253, 300, 505, 506, 1000, 10_000, 65_535]

      test_values.each do |value|
        encoded = described_class.encode_255_uint16(value)
        io = StringIO.new(encoded)
        decoded = described_class.decode_255_uint16(io)
        expect(decoded).to eq(value)
      end
    end
  end

  describe ".decode_255_uint16" do
    it "decodes single byte values" do
      io = StringIO.new([100].pack("C"))
      decoded = described_class.decode_255_uint16(io)
      expect(decoded).to eq(100)
    end

    it "decodes 253 format" do
      encoded = described_class.encode_255_uint16(300)
      io = StringIO.new(encoded)
      decoded = described_class.decode_255_uint16(io)
      expect(decoded).to eq(300)
    end

    it "decodes 254 format" do
      encoded = described_class.encode_255_uint16(1000)
      io = StringIO.new(encoded)
      decoded = described_class.decode_255_uint16(io)
      expect(decoded).to eq(1000)
    end

    it "returns nil on EOF" do
      io = StringIO.new("")
      decoded = described_class.decode_255_uint16(io)
      expect(decoded).to be_nil
    end
  end

  describe Fontisan::Woff2::Directory::Entry do
    describe "initialization" do
      it "creates a new entry" do
        entry = described_class.new
        expect(entry).to be_a(described_class)
      end

      it "initializes with default values" do
        entry = described_class.new
        expect(entry.tag).to be_nil
        expect(entry.flags).to eq(0)
        expect(entry.orig_length).to eq(0)
        expect(entry.transform_length).to be_nil
        expect(entry.offset).to eq(0)
      end
    end

    describe "#known_tag?" do
      it "returns true for known tags" do
        entry = described_class.new
        entry.tag = "head"
        expect(entry.known_tag?).to be true
      end

      it "returns false for custom tags" do
        entry = described_class.new
        entry.tag = "CUST"
        expect(entry.known_tag?).to be false
      end
    end

    describe "#calculate_flags" do
      it "calculates flags for known tag" do
        entry = described_class.new
        entry.tag = "head"
        flags = entry.calculate_flags

        tag_index = Fontisan::Woff2::Directory::KNOWN_TAGS.index("head")
        expect(flags & 0x3F).to eq(tag_index)
      end

      it "calculates flags for custom tag" do
        entry = described_class.new
        entry.tag = "CUST"
        flags = entry.calculate_flags

        expect(flags & 0x3F).to eq(0x3F)
      end

      it "includes transform version in flags" do
        entry = described_class.new
        entry.tag = "glyf"
        flags = entry.calculate_flags

        # For this milestone, transform version should be 3 (TRANSFORM_NONE - not transformed)
        expect((flags >> 6) & 0x03).to eq(3)
      end
    end

    describe "#transformed?" do
      it "returns false when no transformation" do
        entry = described_class.new
        entry.tag = "head"
        expect(entry.transformed?).to be false
      end

      it "returns false when transform_length is nil" do
        entry = described_class.new
        entry.tag = "glyf"
        expect(entry.transformed?).to be false
      end
    end

    describe "#transform_version" do
      it "extracts transform version from flags" do
        entry = described_class.new
        entry.flags = 0b11000001 # Version 3, tag index 1
        expect(entry.transform_version).to eq(3)
      end

      it "returns 0 for no transformation" do
        entry = described_class.new
        entry.flags = 0b00000001 # Version 0
        expect(entry.transform_version).to eq(0)
      end
    end

    describe "#tag_index" do
      it "extracts tag index from flags" do
        entry = described_class.new
        entry.flags = 0b11001010 # Version 3, tag index 10
        expect(entry.tag_index).to eq(10)
      end

      it "handles custom tag index" do
        entry = described_class.new
        entry.flags = 0x3F # Custom tag
        expect(entry.tag_index).to eq(0x3F)
      end
    end

    describe "#transformable?" do
      it "returns true for glyf table" do
        entry = described_class.new
        entry.tag = "glyf"
        expect(entry.transformable?).to be true
      end

      it "returns true for loca table" do
        entry = described_class.new
        entry.tag = "loca"
        expect(entry.transformable?).to be true
      end

      it "returns true for hmtx table" do
        entry = described_class.new
        entry.tag = "hmtx"
        expect(entry.transformable?).to be true
      end

      it "returns false for other tables" do
        entry = described_class.new
        entry.tag = "head"
        expect(entry.transformable?).to be false
      end
    end

    describe "#serialized_size" do
      it "calculates size for known tag without transformation" do
        entry = described_class.new
        entry.tag = "head"
        entry.orig_length = 54

        # 1 (flags) + UIntBase128(54) = 1 + 1 = 2
        expect(entry.serialized_size).to eq(2)
      end

      it "calculates size for custom tag" do
        entry = described_class.new
        entry.tag = "CUST"
        entry.orig_length = 100

        # 1 (flags) + 4 (tag) + UIntBase128(100) = 1 + 4 + 1 = 6
        expect(entry.serialized_size).to eq(6)
      end

      it "includes transform_length when present" do
        entry = described_class.new
        entry.tag = "glyf"
        entry.orig_length = 10000
        entry.transform_length = 8000

        size = entry.serialized_size
        expect(size).to be > 2 # At least flags + 2 UIntBase128 values
      end
    end

    describe "typical entries" do
      it "creates entry for head table" do
        entry = described_class.new
        entry.tag = "head"
        entry.orig_length = 54
        entry.flags = entry.calculate_flags

        expect(entry.known_tag?).to be true
        expect(entry.transformable?).to be false
        expect(entry.transformed?).to be false
      end

      it "creates entry for glyf table" do
        entry = described_class.new
        entry.tag = "glyf"
        entry.orig_length = 25000
        entry.flags = entry.calculate_flags

        expect(entry.known_tag?).to be true
        expect(entry.transformable?).to be true
      end

      it "creates entry for custom table" do
        entry = described_class.new
        entry.tag = "CUST"
        entry.orig_length = 1000
        entry.flags = entry.calculate_flags

        expect(entry.known_tag?).to be false
        expect(entry.tag_index).to eq(0x3F)
      end
    end
  end
end
