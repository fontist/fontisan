# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Loca do
  # Test fixtures acknowledgment:
  # Using Libertinus fonts (OFL licensed) from:
  # https://github.com/alerque/libertinus
  # Copyright © 2012-2023 The Libertinus Project Authors
  #
  # Additional reference implementations:
  # - ttfunk: https://github.com/prawnpdf/ttfunk/blob/master/lib/ttfunk/table/loca.rb
  # - fonttools: https://github.com/fonttools/fonttools/blob/main/Lib/fontTools/ttLib/tables/_l_o_c_a.py
  # - Allsorts: https://github.com/yeslogic/allsorts

  # Helper to build valid loca table binary data in short format (format 0)
  #
  # Based on OpenType specification for loca table structure:
  # https://docs.microsoft.com/en-us/typography/opentype/spec/loca
  #
  # Short format uses uint16 values that are divided by 2 in storage.
  # To get the actual offset, multiply by 2.
  #
  # @param offsets [Array<Integer>] Actual glyph offsets (will be divided by 2)
  # @return [String] Binary data for loca table
  def build_loca_table_short(offsets)
    data = (+"").b

    offsets.each do |offset|
      # Store as offset/2 in uint16
      data << [offset / 2].pack("n")
    end

    data
  end

  # Helper to build valid loca table binary data in long format (format 1)
  #
  # Long format uses uint32 values that are used as-is.
  #
  # @param offsets [Array<Integer>] Glyph offsets
  # @return [String] Binary data for loca table
  def build_loca_table_long(offsets)
    data = (+"").b

    offsets.each do |offset|
      # Store as-is in uint32
      data << [offset].pack("N")
    end

    data
  end

  describe ".read" do
    it "reads short format data" do
      offsets = [0, 100, 200, 300, 400]
      data = build_loca_table_short(offsets)

      loca = described_class.read(data)
      expect(loca).to be_a(described_class)
      expect(loca.raw_data).to eq(data)
    end

    it "reads long format data" do
      offsets = [0, 1000, 2000, 3000, 4000]
      data = build_loca_table_long(offsets)

      loca = described_class.read(data)
      expect(loca).to be_a(described_class)
      expect(loca.raw_data).to eq(data)
    end

    context "with nil or empty data" do
      it "handles nil data gracefully" do
        expect { described_class.read(nil) }.not_to raise_error
      end

      it "handles empty string gracefully" do
        expect { described_class.read("") }.not_to raise_error
      end
    end
  end

  describe "#parse_with_context" do
    context "with short format (format 0)" do
      let(:offsets) { [0, 100, 200, 350, 500, 500, 650] } # 6 glyphs + 1
      let(:data) { build_loca_table_short(offsets) }
      let(:loca) { described_class.read(data) }
      let(:num_glyphs) { 6 }

      before do
        loca.parse_with_context(described_class::FORMAT_SHORT, num_glyphs)
      end

      it "parses offsets correctly" do
        expect(loca.offsets).to eq(offsets)
      end

      it "has correct number of offsets (numGlyphs + 1)" do
        expect(loca.offsets.length).to eq(num_glyphs + 1)
      end

      it "identifies as short format" do
        expect(loca).to be_short_format
        expect(loca).not_to be_long_format
      end

      it "marks table as parsed" do
        expect(loca).to be_parsed
      end
    end

    context "with long format (format 1)" do
      let(:offsets) { [0, 1000, 2500, 4000, 5500, 5500, 7000] } # 6 glyphs + 1
      let(:data) { build_loca_table_long(offsets) }
      let(:loca) { described_class.read(data) }
      let(:num_glyphs) { 6 }

      before do
        loca.parse_with_context(described_class::FORMAT_LONG, num_glyphs)
      end

      it "parses offsets correctly" do
        expect(loca.offsets).to eq(offsets)
      end

      it "has correct number of offsets (numGlyphs + 1)" do
        expect(loca.offsets.length).to eq(num_glyphs + 1)
      end

      it "identifies as long format" do
        expect(loca).to be_long_format
        expect(loca).not_to be_short_format
      end

      it "marks table as parsed" do
        expect(loca).to be_parsed
      end
    end

    context "with validation" do
      it "validates format parameter" do
        data = build_loca_table_short([0, 100])
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(2, 1) # Invalid format
        end.to raise_error(ArgumentError, /indexToLocFormat must be 0/)
      end

      it "validates num_glyphs parameter" do
        data = build_loca_table_short([0, 100])
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(0, 0) # Invalid num_glyphs
        end.to raise_error(ArgumentError, /numGlyphs must be >= 1/)
      end

      it "validates nil format parameter" do
        data = build_loca_table_short([0, 100])
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(nil, 1)
        end.to raise_error(ArgumentError, /indexToLocFormat/)
      end

      it "validates nil num_glyphs parameter" do
        data = build_loca_table_short([0, 100])
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(0, nil)
        end.to raise_error(ArgumentError, /numGlyphs/)
      end

      it "raises error for insufficient data (short format)" do
        # Truncated data
        data = [0].pack("n")
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(0, 2) # Need 3 offsets (2 + 1)
        end.to raise_error(Fontisan::CorruptedTableError, /Insufficient data/)
      end

      it "raises error for insufficient data (long format)" do
        # Truncated data
        data = [0].pack("N")
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(1, 2) # Need 3 offsets (2 + 1)
        end.to raise_error(Fontisan::CorruptedTableError, /Insufficient data/)
      end

      it "raises error for non-monotonic offsets" do
        # Offsets going backwards - corrupted
        offsets = [0, 100, 50, 200] # 50 < 100 is invalid
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)

        expect do
          loca.parse_with_context(0, 3)
        end.to raise_error(Fontisan::CorruptedTableError,
                           /not monotonically increasing/)
      end
    end

    context "with edge cases" do
      it "handles single glyph font" do
        offsets = [0, 100] # 1 glyph + 1 end marker
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)

        loca.parse_with_context(0, 1)
        expect(loca.offsets).to eq(offsets)
      end

      it "handles all empty glyphs" do
        offsets = [0, 0, 0, 0] # All glyphs have size 0
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)

        loca.parse_with_context(0, 3)
        expect(loca.offsets).to eq(offsets)
      end

      it "handles large offsets in long format" do
        offsets = [0, 100000, 200000, 300000]
        data = build_loca_table_long(offsets)
        loca = described_class.read(data)

        loca.parse_with_context(1, 3)
        expect(loca.offsets).to eq(offsets)
      end

      it "handles many glyphs" do
        num_glyphs = 1000
        offsets = (0..(num_glyphs)).map { |i| i * 100 }
        data = build_loca_table_long(offsets)
        loca = described_class.read(data)

        loca.parse_with_context(1, num_glyphs)
        expect(loca.offsets.length).to eq(num_glyphs + 1)
      end
    end
  end

  describe "#offset_for" do
    let(:offsets) { [0, 100, 200, 350, 500, 500, 650] } # 6 glyphs + 1
    let(:data) { build_loca_table_short(offsets) }
    let(:loca) { described_class.read(data) }

    before do
      loca.parse_with_context(0, 6)
    end

    it "returns offset for valid glyph ID" do
      expect(loca.offset_for(0)).to eq(0)
      expect(loca.offset_for(1)).to eq(100)
      expect(loca.offset_for(2)).to eq(200)
      expect(loca.offset_for(3)).to eq(350)
      expect(loca.offset_for(4)).to eq(500)
      expect(loca.offset_for(5)).to eq(500)
    end

    it "returns nil for glyph ID beyond range" do
      expect(loca.offset_for(6)).to be_nil # Only 6 glyphs (0-5)
      expect(loca.offset_for(100)).to be_nil
    end

    it "returns nil for negative glyph ID" do
      expect(loca.offset_for(-1)).to be_nil
    end

    it "raises error if table not parsed" do
      unparsed_loca = described_class.read(data)

      expect do
        unparsed_loca.offset_for(0)
      end.to raise_error(RuntimeError, /not parsed/)
    end
  end

  describe "#size_of" do
    let(:offsets) { [0, 100, 200, 350, 500, 500, 650] } # 6 glyphs + 1
    let(:data) { build_loca_table_short(offsets) }
    let(:loca) { described_class.read(data) }

    before do
      loca.parse_with_context(0, 6)
    end

    it "calculates glyph size correctly" do
      expect(loca.size_of(0)).to eq(100)  # 100 - 0
      expect(loca.size_of(1)).to eq(100)  # 200 - 100
      expect(loca.size_of(2)).to eq(150)  # 350 - 200
      expect(loca.size_of(3)).to eq(150)  # 500 - 350
      expect(loca.size_of(4)).to eq(0)    # 500 - 500 (empty glyph)
      expect(loca.size_of(5)).to eq(150)  # 650 - 500
    end

    it "identifies empty glyphs (size 0)" do
      expect(loca.size_of(4)).to eq(0)
    end

    it "returns nil for glyph ID beyond range" do
      expect(loca.size_of(6)).to be_nil
      expect(loca.size_of(100)).to be_nil
    end

    it "returns nil for negative glyph ID" do
      expect(loca.size_of(-1)).to be_nil
    end

    it "raises error if table not parsed" do
      unparsed_loca = described_class.read(data)

      expect do
        unparsed_loca.size_of(0)
      end.to raise_error(RuntimeError, /not parsed/)
    end
  end

  describe "#empty?" do
    let(:offsets) { [0, 100, 200, 350, 500, 500, 650] } # 6 glyphs + 1
    let(:data) { build_loca_table_short(offsets) }
    let(:loca) { described_class.read(data) }

    before do
      loca.parse_with_context(0, 6)
    end

    it "returns false for non-empty glyphs" do
      expect(loca.empty?(0)).to be false
      expect(loca.empty?(1)).to be false
      expect(loca.empty?(2)).to be false
      expect(loca.empty?(3)).to be false
      expect(loca.empty?(5)).to be false
    end

    it "returns true for empty glyphs (size 0)" do
      expect(loca.empty?(4)).to be true
    end

    it "returns nil for glyph ID beyond range" do
      expect(loca.empty?(6)).to be_nil
      expect(loca.empty?(100)).to be_nil
    end

    it "returns nil for negative glyph ID" do
      expect(loca.empty?(-1)).to be_nil
    end

    it "raises error if table not parsed" do
      unparsed_loca = described_class.read(data)

      expect do
        unparsed_loca.empty?(0)
      end.to raise_error(RuntimeError, /not parsed/)
    end
  end

  describe "#parsed?" do
    let(:data) { build_loca_table_short([0, 100]) }
    let(:loca) { described_class.read(data) }

    it "returns false before parsing" do
      expect(loca).not_to be_parsed
    end

    it "returns true after parsing" do
      loca.parse_with_context(0, 1)
      expect(loca).to be_parsed
    end
  end

  describe "#expected_size" do
    context "with short format" do
      let(:num_glyphs) { 10 }
      let(:offsets) { (0..num_glyphs).map { |i| i * 100 } }
      let(:data) { build_loca_table_short(offsets) }
      let(:loca) { described_class.read(data) }

      before do
        loca.parse_with_context(0, num_glyphs)
      end

      it "calculates correct size for short format" do
        # (numGlyphs + 1) × 2 bytes
        expected = (num_glyphs + 1) * 2
        expect(loca.expected_size).to eq(expected)
      end

      it "matches actual data size" do
        expect(data.bytesize).to eq(loca.expected_size)
      end
    end

    context "with long format" do
      let(:num_glyphs) { 10 }
      let(:offsets) { (0..num_glyphs).map { |i| i * 100 } }
      let(:data) { build_loca_table_long(offsets) }
      let(:loca) { described_class.read(data) }

      before do
        loca.parse_with_context(1, num_glyphs)
      end

      it "calculates correct size for long format" do
        # (numGlyphs + 1) × 4 bytes
        expected = (num_glyphs + 1) * 4
        expect(loca.expected_size).to eq(expected)
      end

      it "matches actual data size" do
        expect(data.bytesize).to eq(loca.expected_size)
      end
    end

    it "returns nil if table not parsed" do
      loca = described_class.read(build_loca_table_short([0, 100]))
      expect(loca.expected_size).to be_nil
    end
  end

  describe "format methods" do
    let(:data) { build_loca_table_short([0, 100]) }
    let(:loca) { described_class.read(data) }

    context "with short format" do
      before do
        loca.parse_with_context(0, 1)
      end

      it "#short_format? returns true" do
        expect(loca.short_format?).to be true
      end

      it "#long_format? returns false" do
        expect(loca.long_format?).to be false
      end

      it "#format returns FORMAT_SHORT" do
        expect(loca.format).to eq(described_class::FORMAT_SHORT)
      end
    end

    context "with long format" do
      let(:data) { build_loca_table_long([0, 100]) }

      before do
        loca.parse_with_context(1, 1)
      end

      it "#long_format? returns true" do
        expect(loca.long_format?).to be true
      end

      it "#short_format? returns false" do
        expect(loca.short_format?).to be false
      end

      it "#format returns FORMAT_LONG" do
        expect(loca.format).to eq(described_class::FORMAT_LONG)
      end
    end
  end

  describe "constants" do
    it "defines FORMAT_SHORT" do
      expect(described_class::FORMAT_SHORT).to eq(0)
    end

    it "defines FORMAT_LONG" do
      expect(described_class::FORMAT_LONG).to eq(1)
    end
  end

  describe "real-world scenarios" do
    context "with typical font structure" do
      it "handles .notdef glyph at position 0" do
        # .notdef is always glyph 0
        offsets = [0, 50, 150, 300] # .notdef size=50, glyph1 size=100, glyph2 size=150
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(0, 3)

        expect(loca.offset_for(0)).to eq(0)
        expect(loca.size_of(0)).to eq(50)
        expect(loca.empty?(0)).to be false
      end

      it "handles empty space glyph" do
        # Space character often has no outline
        offsets = [0, 100, 100, 200] # glyph 1 is empty
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(0, 3)

        expect(loca.size_of(1)).to eq(0)
        expect(loca.empty?(1)).to be true
      end

      it "handles complex glyph with large size" do
        # Some glyphs like '@' can be complex
        offsets = [0, 50, 2000, 2100] # Large glyph at position 1
        data = build_loca_table_long(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(1, 3)

        expect(loca.size_of(1)).to eq(1950)
      end

      it "handles last glyph correctly" do
        offsets = [0, 100, 200, 300, 400]
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(0, 4)

        # Last glyph (index 3)
        expect(loca.offset_for(3)).to eq(300)
        expect(loca.size_of(3)).to eq(100) # 400 - 300
        expect(loca.empty?(3)).to be false
      end
    end

    context "with format selection based on glyf table size" do
      it "uses short format for small glyf tables" do
        # Short format can address up to 65535 × 2 = 131070 bytes
        # This is typical for small fonts
        max_offset = 60000
        offsets = [0, 1000, 2000, max_offset]
        data = build_loca_table_short(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(0, 3)

        expect(loca.short_format?).to be true
        expect(loca.offsets.last).to eq(max_offset)
      end

      it "uses long format for large glyf tables" do
        # Long format needed when glyf table > 131070 bytes
        # This is typical for fonts with many glyphs or complex outlines
        max_offset = 200000
        offsets = [0, 50000, 100000, max_offset]
        data = build_loca_table_long(offsets)
        loca = described_class.read(data)
        loca.parse_with_context(1, 3)

        expect(loca.long_format?).to be true
        expect(loca.offsets.last).to eq(max_offset)
      end
    end
  end

  describe "integration with head and maxp tables" do
    it "uses head.indexToLocFormat to determine format" do
      # This simulates how loca is parsed in context
      offsets = [0, 100, 200, 300]
      data = build_loca_table_short(offsets)
      loca = described_class.read(data)

      # Simulate head table providing format
      index_to_loc_format = 0 # Short format from head table
      num_glyphs = 3 # From maxp table

      loca.parse_with_context(index_to_loc_format, num_glyphs)

      expect(loca.short_format?).to be true
      expect(loca.offsets.length).to eq(num_glyphs + 1)
    end

    it "uses maxp.numGlyphs to determine offset count" do
      # This simulates parsing with maxp context
      num_glyphs = 5
      offsets = (0..num_glyphs).map { |i| i * 100 }
      data = build_loca_table_long(offsets)
      loca = described_class.read(data)

      # Simulate values from head and maxp tables
      loca.parse_with_context(1, num_glyphs)

      expect(loca.offsets.length).to eq(num_glyphs + 1)
      expect(loca.num_glyphs).to eq(num_glyphs)
    end
  end

  describe "integration with real fonts" do
    let(:libertinus_serif_ttf_path) do
      font_fixture_path("Libertinus", "static/TTF/LibertinusSerif-Regular.ttf")
    end

    context "when reading from TrueType font" do
      it "successfully parses loca table from Libertinus Serif TTF" do
        font = Fontisan::TrueTypeFont.from_file(libertinus_serif_ttf_path)
        head = font.table("head")
        maxp = font.table("maxp")

        # These tables are required and should exist
        expect(head).not_to be_nil, "head table should exist in Libertinus font"
        expect(maxp).not_to be_nil, "maxp table should exist in Libertinus font"

        # Get loca table data
        loca_data = font.table_data["loca"]
        expect(loca_data).not_to be_nil,
                                 "loca table should exist in Libertinus font"

        loca = described_class.read(loca_data)
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)

        # Verify table is parsed correctly
        expect(loca).to be_parsed
        expect(loca.offsets.length).to eq(maxp.num_glyphs + 1)

        # Verify first offset is 0 (.notdef glyph)
        expect(loca.offset_for(0)).to eq(0)

        # Verify offsets are monotonically increasing
        loca.offsets.each_cons(2) do |prev, curr|
          expect(curr).to be >= prev
        end

        # Verify some glyphs have data
        non_empty_count = (0...maxp.num_glyphs).count { |i| !loca.empty?(i) }
        expect(non_empty_count).to be > 0
      end
    end
  end
end
