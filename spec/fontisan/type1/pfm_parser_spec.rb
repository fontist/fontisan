# frozen_string_literal: true

RSpec.describe Fontisan::Type1::PFMParser, "with real PFM files" do
  describe "loading PFM format" do
    let(:pfm_path) do
      File.expand_path(
        "../../fixtures/fonts/type1/urw/C059-Bold-generated.pfm", __dir__
      )
    end
    let(:pfm) do
      described_class.parse_file(pfm_path)
    end
    let(:afm) do
      Fontisan::Type1::AFMParser.parse_file(afm_path) if File.exist?(afm_path)
    end
    let(:afm_path) do
      File.expand_path(
        "../../fixtures/fonts/type1/urw/C059-Bold-generated.afm", __dir__
      )
    end

    # Skip test if PFM file doesn't exist yet
    before do
      skip "PFM fixture not yet downloaded from URW Base35" unless File.exist?(pfm_path)
    end

    it "loads PFM file successfully" do
      expect(pfm).to be_a(described_class)
    end

    it "extracts font name from PFM" do
      expect(pfm.font_name).not_to be_nil
      expect(pfm.font_name).to be_a(String)
    end

    it "has character widths" do
      expect(pfm.character_widths).to be_a(Hash)
      expect(pfm.character_widths.count).to be > 0
    end

    it "has kerning pairs" do
      expect(pfm.kerning_pairs).to be_a(Hash)
      # Kerning pairs may be empty in some fonts
    end

    it "provides width for character" do
      # Check a common character index (A = 0 in some fonts, varies by encoding)
      first_char_idx = pfm.character_widths.keys.first
      expect(first_char_idx).not_to be_nil
      width = pfm.width(first_char_idx)
      expect(width).to be_a(Integer)
      expect(width).to be >= 0
    end

    it "provides kerning adjustment" do
      # Kerning may or may not exist
      pfm.kerning_pairs.each do |(left, right), adjustment|
        expect(pfm.kerning(left, right)).to eq(adjustment)
      end
    end

    it "has extended metrics" do
      expect(pfm.extended_metrics).to be_a(Hash)
    end

    it "has copyright string" do
      expect(pfm.copyright).to be_a(String)
    end
  end

  describe "parse from binary data" do
    it "parses minimal PFM content from binary string" do
      # Build PFM content step by step to ensure correct structure
      data = []

      # Version (2 bytes at offset 0)
      data += [0x00, 0x01]

      # dfSize (4 bytes at offset 2)
      data += [0x15, 0x01, 0x00, 0x00]

      # Copyright (60 bytes at offset 6) - Pascal string
      data += [0x16] # Length
      data += [0x43, 0x6f, 0x70, 0x79, 0x72, 0x69, 0x67, 0x68, 0x74, 0x20]  # "Copyrig"
      data += [0x32, 0x30, 0x32, 0x34, 0x20, 0x54, 0x65, 0x73, 0x74, 0x20]  # "ht 2024 Test "
      data += [0x46, 0x6f] # "Fo"
      data += [0x00] * 37 # Padding to 60 bytes

      # dfType (2 bytes at offset 66)
      data += [0x01, 0x00]

      # dfPoints through dfWidthBytes (32 bytes at offset 68)
      data += [0x00, 0x30, 0x00, 0x60, 0x00, 0x60, 0x5c, 0x01] # dfPoints-dfAscent
      data += [0xc8, 0x00, 0x00, 0x00] # dfInternalLeading-dfExternalLeading
      data += [0x00, 0x00, 0x00]  # dfItalic-dfStrikeOut
      data += [0x90, 0x01, 0x00]  # dfWeight-dfCharSet
      data += [0x00, 0x00, 0x00, 0x00] # dfPixWidth-dfPixHeight
      data += [0x00, 0x00, 0x00, 0x00, 0x00] # dfPitchAndFamily-dfMaxWidth
      data += [0x00, 0xff, 0x00, 0x20, 0x00, 0x00] # dfFirstChar-dfWidthBytes

      # dfDevice (4 bytes at offset 101)
      data += [0x00, 0x00, 0x00, 0x00]

      # dfFace (4 bytes at offset 105) - offset to font name at 256
      data += [0x00, 0x01, 0x00, 0x00]

      # dfBitsPointer through dfReserved (35 bytes at offset 109)
      data += [0x00] * 35

      # Padding to offset 256 (112 bytes at offset 144)
      data += [0x00] * 112

      # Font name at offset 256 (Pascal string)
      data += [0x09, 0x54, 0x65, 0x73, 0x74, 0x46, 0x6f, 0x6e, 0x74, 0x00]

      pfm_content = data.pack("C*")
      pfm = described_class.parse(pfm_content)

      expect(pfm.font_name.strip).to eq("TestFont")
      expect(pfm.copyright).to include("Copyright 2024")
    end

    it "handles PFM with character width table" do
      data = []

      # Version (2 bytes)
      data += [0x00, 0x01]

      # dfSize (4 bytes)
      data += [0x1e, 0x01, 0x00, 0x00]

      # Copyright (60 bytes)
      data += [0x07] # Length
      data += [0x43, 0x6f, 0x70, 0x79, 0x72, 0x69, 0x67, 0x68, 0x74] # "Copyright"
      data += [0x00] * 50 # Padding to 60 bytes total

      # dfType and following fields
      data += [0x01, 0x00] # dfType
      data += [0x00, 0x30, 0x00, 0x60, 0x00, 0x60, 0x5c, 0x01] # dfPoints-dfAscent
      data += [0xc8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] # dfInternalLeading-dfStrikeOut
      data += [0x90, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] # dfWeight-dfPixHeight
      data += [0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x20, 0x00, 0x00] # dfPitchAndFamily-dfWidthBytes

      # dfDevice
      data += [0x00, 0x00, 0x00, 0x00]

      # Calculate font name offset (will be at 258)
      # Current position: 105, so after dfFace (4 bytes) = 109
      # After dfBitsPointer through dfReserved (35 bytes) = 144
      # After padding to 256 = 256
      # After 2 more bytes = 258
      data += [0x02, 0x01, 0x00, 0x00] # dfFace offset to 258

      # dfBitsPointer through dfReserved
      data += [0x00] * 35

      # Padding to offset 256 (currently at 109, need 147 more)
      data += [0x00] * (256 - data.length)

      # Padding to offset 258 (need 2 more)
      data += [0x00] * 2

      # Font name at offset 258
      data += [0x09, 0x54, 0x65, 0x73, 0x74, 0x46, 0x6f, 0x6e, 0x74, 0x00]

      # Extent table at offset 268
      data += [0x03, 0x00] # Number of extents
      data += [0xf4, 0x01, 0xdc, 0x01, 0x14, 0x02] # Extent values: 500, 468, 532

      # Update dfExtentTable offset at position 121
      extent_table_offset = 268
      data[121] = extent_table_offset & 0xff
      data[122] = (extent_table_offset >> 8) & 0xff
      data[123] = (extent_table_offset >> 16) & 0xff
      data[124] = (extent_table_offset >> 24) & 0xff

      pfm_content = data.pack("C*")
      pfm = described_class.parse(pfm_content)

      expect(pfm.font_name.strip).to eq("TestFont")
      expect(pfm.character_widths.count).to eq(3)
      expect(pfm.width(0)).to eq(500)
      expect(pfm.width(1)).to eq(476)
      expect(pfm.width(2)).to eq(532)
    end

    it "handles PFM with kerning pairs" do
      data = []

      # Version
      data += [0x00, 0x01]

      # dfSize
      data += [0x26, 0x01, 0x00, 0x00]

      # Copyright
      data += [0x07] # Length
      data += [0x43, 0x6f, 0x70, 0x79, 0x72, 0x69, 0x67, 0x68, 0x74] # "Copyright"
      data += [0x00] * 50 # Padding to 60 bytes total

      # dfType and following fields
      data += [0x01, 0x00] # dfType
      data += [0x00, 0x30, 0x00, 0x60, 0x00, 0x60, 0x5c, 0x01] # dfPoints-dfAscent
      data += [0xc8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] # dfInternalLeading-dfStrikeOut
      data += [0x90, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] # dfWeight-dfPixHeight
      data += [0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x20, 0x00, 0x00] # dfPitchAndFamily-dfWidthBytes

      # dfDevice
      data += [0x00, 0x00, 0x00, 0x00]

      # Calculate font name offset (will be at 258)
      data += [0x02, 0x01, 0x00, 0x00] # dfFace offset to 258

      # dfBitsPointer through dfReserved
      data += [0x00] * 4  # dfBitsPointer
      data += [0x00] * 4  # dfBitsOffset
      data += [0x00] * 4  # dfExtMetrics offset
      data += [0x00] * 4  # dfExtentTable offset
      data += [0x00] * 4  # dfOriginTable offset
      data += [0x00] * 4  # dfPairKernTable offset (will be updated)
      data += [0x00] * 4  # dfTrackKernTable offset
      data += [0x00] * 4  # dfDriverInfo offset
      data += [0x00] * 4  # dfReserved

      # Padding to offset 256 (currently at 109, need 147 more)
      data += [0x00] * (256 - data.length)

      # Padding to offset 258 (need 2 more)
      data += [0x00] * 2

      # Font name at offset 258
      data += [0x09, 0x54, 0x65, 0x73, 0x74, 0x46, 0x6f, 0x6e, 0x74, 0x00]

      # Kerning table at offset 268
      kern_table_offset = data.length
      data += [0x02, 0x00]  # Number of pairs
      data += [0x0c, 0x00]  # Size
      data += [0x00, 0x00, 0x01, 0x00, 0xce, 0xff]  # Pair (0,1) -> -50
      data += [0x01, 0x00, 0x02, 0x00, 0xe2, 0xff]  # Pair (1,2) -> -30

      # Update dfPairKernTable offset at position 129
      data[129] = kern_table_offset & 0xff
      data[130] = (kern_table_offset >> 8) & 0xff
      data[131] = (kern_table_offset >> 16) & 0xff
      data[132] = (kern_table_offset >> 24) & 0xff

      pfm_content = data.pack("C*")
      pfm = described_class.parse(pfm_content)

      expect(pfm.font_name.strip).to eq("TestFont")
      expect(pfm.kerning_pairs.count).to eq(2)
      expect(pfm.kerning(0, 1)).to eq(-50)
      expect(pfm.kerning(1, 2)).to eq(-30)
    end
  end

  describe "error handling" do
    it "raises error for nil path" do
      expect { described_class.parse_file(nil) }
        .to raise_error(ArgumentError, /Path cannot be nil/)
    end

    it "raises error for missing file" do
      expect { described_class.parse_file("nonexistent.pfm") }
        .to raise_error(Fontisan::Error, /PFM file not found/)
    end
  end
end
