# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff"
require "fontisan/tables/cff/encoding"

RSpec.describe Fontisan::Tables::Cff::Encoding do
  describe "#initialize" do
    context "with predefined encoding ID" do
      it "loads Standard encoding" do
        encoding = described_class.new(0, 100)

        expect(encoding.format).to eq(:predefined)
        expect(encoding.glyph_id(0)).to eq(0) # .notdef at code 0
        expect(encoding.glyph_id(32)).to be > 0 # Space character
      end

      it "loads Expert encoding" do
        encoding = described_class.new(1, 50)

        expect(encoding.format).to eq(:predefined)
        expect(encoding.glyph_id(0)).to eq(0) # .notdef at code 0
      end
    end

    context "with binary data" do
      it "parses format 0 (array)" do
        # Format 0: format byte + nCodes + codes
        data = [
          0,  # Format 0
          3,  # nCodes (3 glyphs excluding .notdef)
          65, # Code for GID 1
          66, # Code for GID 2
          67, # Code for GID 3
        ].pack("C*")

        encoding = described_class.new(data, 4)

        expect(encoding.format).to eq(:array)
        expect(encoding.glyph_id(0)).to eq(0)   # .notdef
        expect(encoding.glyph_id(65)).to eq(1)  # 'A'
        expect(encoding.glyph_id(66)).to eq(2)  # 'B'
        expect(encoding.glyph_id(67)).to eq(3)  # 'C'
      end

      it "parses format 1 (ranges)" do
        # Format 1: format byte + nRanges + ranges (first code, nLeft)
        data = [
          1,  # Format 1
          2,  # nRanges (2 ranges)
          65, 2, # Range: codes 65-67 (nLeft=2 means 3 codes)
          70, 1 # Range: codes 70-71 (nLeft=1 means 2 codes)
        ].pack("C*")

        encoding = described_class.new(data, 6)

        expect(encoding.format).to eq(:range)
        expect(encoding.glyph_id(0)).to eq(0)   # .notdef
        expect(encoding.glyph_id(65)).to eq(1)  # First of first range
        expect(encoding.glyph_id(66)).to eq(2)
        expect(encoding.glyph_id(67)).to eq(3)
        expect(encoding.glyph_id(70)).to eq(4)  # First of second range
        expect(encoding.glyph_id(71)).to eq(5)
      end

      it "parses format with supplement" do
        # Format 0 with supplement: high bit set, supplement data follows
        data = [
          0x80, # Format 0 with supplement (bit 7 set)
          2,    # nCodes
          65,   # Code for GID 1
          66,   # Code for GID 2
          1,    # nSups (1 supplemental mapping)
          90,   # Supplemental code
          0, 10 # SID for supplemental code
        ].pack("C*")

        encoding = described_class.new(data, 3)

        expect(encoding.format).to eq(:array)
        expect(encoding.has_supplement?).to be true
        expect(encoding.glyph_id(65)).to eq(1)
        expect(encoding.glyph_id(66)).to eq(2)
      end
    end
  end

  describe "#glyph_id" do
    let(:data) do
      [
        0,  # Format 0
        3,  # nCodes
        65, # Code for GID 1
        66, # Code for GID 2
        67, # Code for GID 3
      ].pack("C*")
    end
    let(:encoding) { described_class.new(data, 4) }

    it "returns GID for valid character code" do
      expect(encoding.glyph_id(0)).to eq(0)
      expect(encoding.glyph_id(65)).to eq(1)
      expect(encoding.glyph_id(66)).to eq(2)
      expect(encoding.glyph_id(67)).to eq(3)
    end

    it "returns nil for unmapped character code" do
      expect(encoding.glyph_id(68)).to be_nil
      expect(encoding.glyph_id(255)).to be_nil
    end
  end

  describe "#char_code" do
    let(:data) do
      [
        0,  # Format 0
        3,  # nCodes
        65, # Code for GID 1
        66, # Code for GID 2
        67, # Code for GID 3
      ].pack("C*")
    end
    let(:encoding) { described_class.new(data, 4) }

    it "returns character code for valid GID" do
      expect(encoding.char_code(0)).to eq(0)
      expect(encoding.char_code(1)).to eq(65)
      expect(encoding.char_code(2)).to eq(66)
      expect(encoding.char_code(3)).to eq(67)
    end

    it "returns nil for unmapped GID" do
      expect(encoding.char_code(10)).to be_nil
      expect(encoding.char_code(999)).to be_nil
    end
  end

  describe "#format" do
    it "returns :array for format 0" do
      data = [0, 1, 65].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.format).to eq(:array)
    end

    it "returns :range for format 1" do
      data = [1, 1, 65, 0].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.format).to eq(:range)
    end

    it "returns :predefined for predefined encodings" do
      encoding = described_class.new(0, 10)

      expect(encoding.format).to eq(:predefined)
    end
  end

  describe "#has_supplement?" do
    it "returns false for format without supplement" do
      data = [0, 1, 65].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.has_supplement?).to be false
    end

    it "returns true for format with supplement" do
      data = [0x80, 1, 65, 0].pack("C*") # Format 0 with supplement bit set
      encoding = described_class.new(data, 2)

      expect(encoding.has_supplement?).to be true
    end
  end

  describe "error handling" do
    it "raises error for invalid format" do
      data = [99].pack("C") # Invalid format

      expect do
        described_class.new(data, 5)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Invalid Encoding format/)
    end

    it "raises error for truncated data" do
      data = [0].pack("C") # Format 0 with no nCodes

      expect do
        described_class.new(data, 5)
      end.to raise_error(Fontisan::CorruptedTableError)
    end
  end

  describe "predefined encodings" do
    context "Standard encoding" do
      let(:encoding) { described_class.new(0, 100) }

      it "maps common ASCII characters" do
        expect(encoding.glyph_id(0)).to eq(0) # .notdef
        expect(encoding.glyph_id(32)).to be > 0 # Space
        expect(encoding.glyph_id(65)).to be > 0 # 'A'
        expect(encoding.glyph_id(97)).to be > 0 # 'a'
      end

      it "provides reverse mapping" do
        gid_for_space = encoding.glyph_id(32)
        expect(encoding.char_code(gid_for_space)).to eq(32)
      end
    end

    context "Expert encoding" do
      let(:encoding) { described_class.new(1, 50) }

      it "maps expert character codes" do
        expect(encoding.glyph_id(0)).to eq(0) # .notdef
        # Expert encoding maps special characters
        expect(encoding.glyph_id(32)).to be > 0
      end
    end
  end

  describe "boundary conditions" do
    it "handles single glyph (only .notdef)" do
      encoding = described_class.new(0, 1)

      expect(encoding.glyph_id(0)).to eq(0)
      expect(encoding.char_code(0)).to eq(0)
    end

    it "handles format 0 with maximum codes" do
      # Create encoding with many codes
      data = [0, 10] + (65..74).to_a
      encoding = described_class.new(data.pack("C*"), 11)

      expect(encoding.glyph_id(65)).to eq(1)
      expect(encoding.glyph_id(74)).to eq(10)
    end

    it "handles format 1 with multiple ranges" do
      # Multiple small ranges
      data = [
        1,     # Format 1
        3,     # 3 ranges
        65, 0, # Range: code 65 (1 code)
        70, 0, # Range: code 70 (1 code)
        75, 0 # Range: code 75 (1 code)
      ].pack("C*")

      encoding = described_class.new(data, 4)

      expect(encoding.glyph_id(65)).to eq(1)
      expect(encoding.glyph_id(70)).to eq(2)
      expect(encoding.glyph_id(75)).to eq(3)
    end

    it "handles format 1 with wide range" do
      # Single range covering many codes
      data = [
        1,      # Format 1
        1,      # 1 range
        65, 25 # Range: codes 65-90 (26 codes)
      ].pack("C*")

      encoding = described_class.new(data, 27)

      expect(encoding.glyph_id(65)).to eq(1)  # 'A'
      expect(encoding.glyph_id(90)).to eq(26) # 'Z'
      expect(encoding.char_code(1)).to eq(65)
      expect(encoding.char_code(26)).to eq(90)
    end
  end

  describe "bidirectional mapping consistency" do
    let(:data) do
      [
        1,     # Format 1
        2,     # 2 ranges
        65, 2, # Range: codes 65-67
        70, 1 # Range: codes 70-71
      ].pack("C*")
    end
    let(:encoding) { described_class.new(data, 6) }

    it "maintains consistency between code-to-gid and gid-to-code" do
      # Test forward and reverse mapping
      (1..5).each do |gid|
        code = encoding.char_code(gid)
        expect(code).not_to be_nil
        expect(encoding.glyph_id(code)).to eq(gid)
      end
    end
  end

  describe "format byte parsing" do
    it "extracts format from lower 7 bits" do
      # Format 0 without supplement
      data = [0, 1, 65].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.format).to eq(:array)
      expect(encoding.has_supplement?).to be false
    end

    it "extracts supplement flag from bit 7" do
      # Format 0 with supplement (0x80 = 10000000)
      data = [0x80, 1, 65, 0].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.format).to eq(:array)
      expect(encoding.has_supplement?).to be true
    end

    it "handles format 1 with supplement" do
      # Format 1 with supplement (0x81 = 10000001)
      data = [0x81, 1, 65, 0, 0].pack("C*")
      encoding = described_class.new(data, 2)

      expect(encoding.format).to eq(:range)
      expect(encoding.has_supplement?).to be true
    end
  end
end
