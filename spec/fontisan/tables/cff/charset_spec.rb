# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff"
require "fontisan/tables/cff/charset"

RSpec.describe Fontisan::Tables::Cff::Charset do
  let(:mock_cff_table) do
    double("Cff").tap do |cff|
      allow(cff).to receive(:string_for_sid) { |sid| "glyph#{sid}" }
    end
  end

  describe "#initialize" do
    context "with predefined charset ID" do
      it "loads ISOAdobe charset" do
        charset = described_class.new(0, 10, mock_cff_table)

        expect(charset.format).to eq(:predefined)
        expect(charset.glyph_name(0)).to eq(".notdef")
        expect(charset.glyph_names.size).to eq(10)
      end

      it "loads Expert charset" do
        charset = described_class.new(1, 10, mock_cff_table)

        expect(charset.format).to eq(:predefined)
        expect(charset.glyph_name(0)).to eq(".notdef")
      end

      it "loads Expert Subset charset" do
        charset = described_class.new(2, 10, mock_cff_table)

        expect(charset.format).to eq(:predefined)
        expect(charset.glyph_name(0)).to eq(".notdef")
      end
    end

    context "with binary data" do
      it "parses format 0 (array)" do
        # Format 0: format byte + SIDs
        data = [
          0,    # Format 0
          0, 1, # SID 1
          0, 2, # SID 2
          0, 3 # SID 3
        ].pack("C*")

        charset = described_class.new(data, 4, mock_cff_table)

        expect(charset.format).to eq(:array)
        expect(charset.glyph_name(0)).to eq(".notdef")
        expect(charset.glyph_name(1)).to eq("glyph1")
        expect(charset.glyph_name(2)).to eq("glyph2")
        expect(charset.glyph_name(3)).to eq("glyph3")
      end

      it "parses format 1 (range with 8-bit counts)" do
        # Format 1: format byte + ranges (first SID, nLeft)
        data = [
          1, # Format 1
          0, 10, 2, # Range: SID 10-12 (nLeft=2 means 3 glyphs)
          0, 20, 1 # Range: SID 20-21 (nLeft=1 means 2 glyphs)
        ].pack("C*")

        charset = described_class.new(data, 6, mock_cff_table)

        expect(charset.format).to eq(:range_8)
        expect(charset.glyph_name(0)).to eq(".notdef")
        expect(charset.glyph_name(1)).to eq("glyph10")
        expect(charset.glyph_name(2)).to eq("glyph11")
        expect(charset.glyph_name(3)).to eq("glyph12")
        expect(charset.glyph_name(4)).to eq("glyph20")
        expect(charset.glyph_name(5)).to eq("glyph21")
      end

      it "parses format 2 (range with 16-bit counts)" do
        # Format 2: format byte + ranges (first SID, nLeft as uint16)
        data = [
          2,       # Format 2
          0, 10,   # First SID 10
          0, 2,    # nLeft 2 (means 3 glyphs)
          0, 20,   # First SID 20
          0, 1 # nLeft 1 (means 2 glyphs)
        ].pack("C*")

        charset = described_class.new(data, 6, mock_cff_table)

        expect(charset.format).to eq(:range_16)
        expect(charset.glyph_name(0)).to eq(".notdef")
        expect(charset.glyph_name(1)).to eq("glyph10")
        expect(charset.glyph_name(2)).to eq("glyph11")
        expect(charset.glyph_name(3)).to eq("glyph12")
        expect(charset.glyph_name(4)).to eq("glyph20")
        expect(charset.glyph_name(5)).to eq("glyph21")
      end
    end
  end

  describe "#glyph_name" do
    let(:data) do
      [
        0,    # Format 0
        0, 1, # SID 1
        0, 2 # SID 2
      ].pack("C*")
    end
    let(:charset) { described_class.new(data, 3, mock_cff_table) }

    it "returns glyph name for valid GID" do
      expect(charset.glyph_name(0)).to eq(".notdef")
      expect(charset.glyph_name(1)).to eq("glyph1")
      expect(charset.glyph_name(2)).to eq("glyph2")
    end

    it "returns nil for invalid GID" do
      expect(charset.glyph_name(10)).to be_nil
      expect(charset.glyph_name(-1)).to be_nil
    end
  end

  describe "#glyph_id" do
    let(:data) do
      [
        0,    # Format 0
        0, 1, # SID 1
        0, 2 # SID 2
      ].pack("C*")
    end
    let(:charset) { described_class.new(data, 3, mock_cff_table) }

    it "returns GID for valid glyph name" do
      expect(charset.glyph_id(".notdef")).to eq(0)
      expect(charset.glyph_id("glyph1")).to eq(1)
      expect(charset.glyph_id("glyph2")).to eq(2)
    end

    it "returns nil for invalid glyph name" do
      expect(charset.glyph_id("nonexistent")).to be_nil
    end
  end

  describe "#format" do
    it "returns :array for format 0" do
      data = [0, 0, 1].pack("C*")
      charset = described_class.new(data, 2, mock_cff_table)

      expect(charset.format).to eq(:array)
    end

    it "returns :range_8 for format 1" do
      data = [1, 0, 10, 0].pack("C*")
      charset = described_class.new(data, 2, mock_cff_table)

      expect(charset.format).to eq(:range_8)
    end

    it "returns :range_16 for format 2" do
      data = [2, 0, 10, 0, 0].pack("C*")
      charset = described_class.new(data, 2, mock_cff_table)

      expect(charset.format).to eq(:range_16)
    end

    it "returns :predefined for predefined charsets" do
      charset = described_class.new(0, 5, mock_cff_table)

      expect(charset.format).to eq(:predefined)
    end
  end

  describe "error handling" do
    it "raises error for invalid format" do
      data = [99].pack("C") # Invalid format

      expect do
        described_class.new(data, 5, mock_cff_table)
      end.to raise_error(Fontisan::CorruptedTableError,
                         /Invalid Charset format/)
    end

    it "raises error for truncated data" do
      data = [0].pack("C") # Format 0 with no SIDs

      expect do
        described_class.new(data, 5, mock_cff_table)
      end.to raise_error(Fontisan::CorruptedTableError)
    end
  end

  describe "integration with CFF string table" do
    let(:cff_table) do
      double("Cff").tap do |cff|
        allow(cff).to receive(:string_for_sid) do |sid|
          case sid
          when 1 then "A"
          when 2 then "B"
          when 3 then "C"
          else ".notdef"
          end
        end
      end
    end

    it "resolves SIDs to glyph names via CFF table" do
      data = [
        0,    # Format 0
        0, 1, # SID 1 -> "A"
        0, 2, # SID 2 -> "B"
        0, 3 # SID 3 -> "C"
      ].pack("C*")

      charset = described_class.new(data, 4, cff_table)

      expect(charset.glyph_name(1)).to eq("A")
      expect(charset.glyph_name(2)).to eq("B")
      expect(charset.glyph_name(3)).to eq("C")
      expect(charset.glyph_id("A")).to eq(1)
      expect(charset.glyph_id("B")).to eq(2)
      expect(charset.glyph_id("C")).to eq(3)
    end
  end

  describe "boundary conditions" do
    it "handles single glyph (only .notdef)" do
      charset = described_class.new(0, 1, mock_cff_table)

      expect(charset.glyph_names.size).to eq(1)
      expect(charset.glyph_name(0)).to eq(".notdef")
    end

    it "handles large glyph counts in format 1" do
      # Format 1 with a range covering many glyphs
      data = [
        1,      # Format 1
        0, 100, # First SID 100
        99 # nLeft 99 (means 100 glyphs)
      ].pack("C*")

      charset = described_class.new(data, 101, mock_cff_table)

      expect(charset.glyph_names.size).to eq(101)
      expect(charset.glyph_name(1)).to eq("glyph100")
      expect(charset.glyph_name(100)).to eq("glyph199")
    end

    it "handles multiple ranges in format 1" do
      # Multiple small ranges
      data = [
        1, # Format 1
        0, 10, 0, # Range: SID 10 (1 glyph)
        0, 20, 0, # Range: SID 20 (1 glyph)
        0, 30, 0 # Range: SID 30 (1 glyph)
      ].pack("C*")

      charset = described_class.new(data, 4, mock_cff_table)

      expect(charset.glyph_name(1)).to eq("glyph10")
      expect(charset.glyph_name(2)).to eq("glyph20")
      expect(charset.glyph_name(3)).to eq("glyph30")
    end

    it "stops parsing when reaching num_glyphs" do
      # Format 1 with more ranges than needed
      data = [
        1, # Format 1
        0, 10, 5, # Range: SID 10-15 (6 glyphs: 10, 11, 12, 13, 14, 15)
        0, 20, 5 # Range: SID 20-25 (would be 6 more, but we only need 4 total)
      ].pack("C*")

      charset = described_class.new(data, 4, mock_cff_table)

      # With num_glyphs=4, we get: GID 0=.notdef, GID 1=SID10, GID 2=SID11, GID 3=SID12
      expect(charset.glyph_names.size).to eq(4)
      expect(charset.glyph_name(3)).to eq("glyph12")
    end
  end
end
