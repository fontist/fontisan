# frozen_string_literal: true

RSpec.describe Fontisan::Type1::CharStringConverter do
  let(:converter) { described_class.new }

  describe "#initialize" do
    it "creates a new converter" do
      expect(converter).to be_a(described_class)
    end

    it "accepts charstrings dictionary" do
      charstrings = Fontisan::Type1::CharStrings.new
      conv = described_class.new(charstrings)

      expect(conv).to be_a(described_class)
    end
  end

  describe "#convert" do
    it "converts hmoveto command" do
      # hmoveto: horizontal moveto
      # Type 1: 22
      # CFF: 22 (same)
      type1_cs = "\x16".b # hmoveto (22)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x16".b)
    end

    it "converts vmoveto command" do
      # vmoveto: vertical moveto
      # Type 1: 4
      # CFF: 4 (same)
      type1_cs = "\x04".b # vmoveto (4)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x04".b)
    end

    it "converts rlineto command" do
      # rlineto: relative line to
      # Type 1: 5
      # CFF: 5 (same)
      type1_cs = "\x05".b # rlineto (5)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x05".b)
    end

    it "converts rrcurveto command" do
      # rrcurveto: relative curve to
      # Type 1: 8
      # CFF: 8 (same)
      type1_cs = "\x08".b # rrcurveto (8)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x08".b)
    end

    it "converts endchar command" do
      # endchar
      # Type 1: 14
      # CFF: 14 (same)
      type1_cs = "\x0E".b # endchar (14)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x0E".b)
    end

    it "converts number with hmoveto" do
      # hmoveto with argument
      # Type 1: number (11) + hmoveto (22)
      # For small numbers in Type 1: value + 139
      # 11 + 139 = 150 (0x96)
      type1_cs = "\x96\x16".b # 150, hmoveto
      cff_cs = converter.convert(type1_cs)

      # CFF encoding for 11: 11 is in range -107 to 107
      # 11 + 139 = 150 (0x96)
      # hmoveto: 22 (0x16)
      expect(cff_cs).to eq("\x96\x16".b) # 150, 22
    end

    it "converts small positive number" do
      # Small number (50) in Type 1 encoding: 50 + 139 = 189 (0xBD)
      type1_cs = "\xBD".b
      cff_cs = converter.convert(type1_cs)

      # CFF encoding: 50 + 139 = 189
      expect(cff_cs).to eq("\xBD".b)
    end

    it "converts small negative number" do
      # Small number (-50) in Type 1 encoding: -50 + 139 = 89 (0x59)
      type1_cs = "\x59".b
      cff_cs = converter.convert(type1_cs)

      # CFF encoding: -50 + 139 = 89
      expect(cff_cs).to eq("\x59".b)
    end

    it "converts zero" do
      # Zero in Type 1 encoding: 0 + 139 = 139 (0x8B)
      type1_cs = "\x8B".b
      cff_cs = converter.convert(type1_cs)

      # CFF encoding: 0 + 139 = 139
      expect(cff_cs).to eq("\x8B".b)
    end

    it "converts hstem hint operator" do
      # hstem: horizontal stem hint
      # Type 1: 1
      # CFF: 1 (same)
      type1_cs = "\x01".b # hstem (1)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x01".b)
    end

    it "converts vstem hint operator" do
      # vstem: vertical stem hint
      # Type 1: 3
      # CFF: 3 (same)
      type1_cs = "\x03".b # vstem (3)
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("\x03".b)
    end

    it "handles empty CharString" do
      type1_cs = ""
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("")
    end

    it "handles nil CharString" do
      type1_cs = nil
      cff_cs = converter.convert(type1_cs)

      expect(cff_cs).to eq("")
    end
  end

  describe "#seac?" do
    it "returns false for CharString without seac" do
      type1_cs = "\x8B\x16".b # 0, hmoveto

      expect(converter.seac?(type1_cs)).to be false
    end

    it "returns true for CharString with seac" do
      # seac operator: escape (12) + 6
      # Format: asb adx ady bchar achar seac
      # asb = 0, adx = 100, ady = 50, bchar = 65, achar = 96
      # Numbers: 139, 239, 189, 204, 235
      type1_cs = "\x8B\xEF\xBD\xCC\xEB\x0C\x06".b

      expect(converter.seac?(type1_cs)).to be true
    end
  end

  describe "#convert_commands" do
    it "converts multiple commands" do
      # hmoveto with number
      # 100 + 139 = 239 (0xEF)
      type1_cs = "\xEF\x16".b # 100, hmoveto

      parser = Fontisan::Type1::CharStrings::CharStringParser.new
      commands = parser.parse(type1_cs)

      cff_cs = converter.convert_commands(commands)

      # CFF: 100 - 108 = -8 (wait, this is positive)
      # 100 + 139 = 239, which is in 2-byte range
      # 100 - 108 = -8? No, 100 is >= 108
      # 100 - 108 = -8, but that's for the 2-byte encoding
      # Actually: 100 is >= 108 and <= 1131
      # So: 100 - 108 = -8? That doesn't seem right
      # Let me check: for 108-1131, we use (value - 108) encoded as 2 bytes
      # 100 - 108 = -8? No wait, the encoding is different
      # For 108-1131: first byte is 247 + (value >> 8), second is value & 0xFF
      # 100 - 108 = -8? I'm confused

      # Actually looking at the code:
      # For 108-1131: value -= 108, then encode
      # So for 100: 100 is less than 108, so it falls in the 1-byte range
      # 100 + 139 = 239, which is 0xEF

      expect(cff_cs).to eq("\xEF\x16".b) # Should be same
    end
  end

  describe "#expand_seac" do
    it "returns endchar for seac composites (placeholder)" do
      seac_data = {
        base: 65,    # 'A'
        accent: 96,  # '`'
        adx: 100,
        ady: 50,
      }

      result = converter.expand_seac(seac_data)

      # Should return endchar as placeholder for now
      expect(result).to eq("\x0E".b)
    end
  end

  describe "CFF number encoding" do
    it "encodes 1-byte numbers correctly" do
      # Test encode_cff_number for range -107 to 107
      expect(converter.send(:encode_cff_number, 0)).to eq("\x8B".b)   # 0 + 139 = 139
      expect(converter.send(:encode_cff_number, 50)).to eq("\xBD".b)  # 50 + 139 = 189
      expect(converter.send(:encode_cff_number, -50)).to eq("\x59".b) # -50 + 139 = 89
      expect(converter.send(:encode_cff_number, 107)).to eq("\xF6".b) # 107 + 139 = 246
      expect(converter.send(:encode_cff_number, -107)).to eq("\x20".b) # -107 + 139 = 32
    end

    it "encodes 2-byte positive numbers" do
      # Test encode_cff_number for range 108 to 1131
      result_150 = converter.send(:encode_cff_number, 150)
      expect(result_150.length).to eq(2)
      expect(result_150.getbyte(0)).to be_between(247, 250) # First byte indicates 2-byte positive

      result_1000 = converter.send(:encode_cff_number, 1000)
      expect(result_1000.length).to eq(2)
      expect(result_1000.getbyte(0)).to be_between(247, 250)
    end

    it "encodes 2-byte negative numbers" do
      # Test encode_cff_number for range -1131 to -108
      result_neg_150 = converter.send(:encode_cff_number, -150)
      expect(result_neg_150.length).to eq(2)
      expect(result_neg_150.getbyte(0)).to be_between(251, 254) # First byte indicates 2-byte negative

      result_neg_1000 = converter.send(:encode_cff_number, -1000)
      expect(result_neg_1000.length).to eq(2)
      expect(result_neg_1000.getbyte(0)).to be_between(251, 254)
    end
  end
end
