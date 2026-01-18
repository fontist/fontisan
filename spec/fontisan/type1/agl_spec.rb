# frozen_string_literal: true

RSpec.describe Fontisan::Type1::AGL do
  describe ".glyph_name_for_unicode" do
    it "returns glyph name for ASCII space" do
      expect(described_class.glyph_name_for_unicode(0x0020)).to eq("space")
    end

    it "returns glyph name for ASCII letters" do
      expect(described_class.glyph_name_for_unicode(0x0041)).to eq("A")
      expect(described_class.glyph_name_for_unicode(0x0061)).to eq("a")
    end

    it "returns glyph name for Latin-1 supplement" do
      expect(described_class.glyph_name_for_unicode(0x00C0)).to eq("Agrave")
      expect(described_class.glyph_name_for_unicode(0x00E9)).to eq("eacute")
    end

    it "returns uniXXXX name for codepoint not in AGL" do
      result = described_class.glyph_name_for_unicode(0x1234)

      expect(result).to eq("uni1234")
    end

    it "pads uniXXXX to 4 digits for BMP" do
      result = described_class.glyph_name_for_unicode(0x0241)

      expect(result).to eq("uni0241")
    end

    it "returns proper format for 4-digit hex" do
      result = described_class.glyph_name_for_unicode(0xABCD)

      expect(result).to eq("uniABCD")
    end
  end

  describe ".unicode_for_glyph_name" do
    it "returns codepoint for ASCII space" do
      expect(described_class.unicode_for_glyph_name("space")).to eq(0x0020)
    end

    it "returns codepoint for ASCII letters" do
      expect(described_class.unicode_for_glyph_name("A")).to eq(0x0041)
      expect(described_class.unicode_for_glyph_name("a")).to eq(0x0061)
    end

    it "returns codepoint for Latin-1 supplement" do
      expect(described_class.unicode_for_glyph_name("Agrave")).to eq(0x00C0)
      expect(described_class.unicode_for_glyph_name("eacute")).to eq(0x00E9)
    end

    it "returns codepoint for uniXXXX name" do
      result = described_class.unicode_for_glyph_name("uni1234")

      expect(result).to eq(0x1234)
    end

    it "returns codepoint for uXXXXX name" do
      result = described_class.unicode_for_glyph_name("u12345")

      expect(result).to eq(0x12345)
    end

    it "returns nil for unknown glyph name" do
      result = described_class.unicode_for_glyph_name("not_a_real_glyph")

      expect(result).to be_nil
    end

    it "returns nil for empty string" do
      result = described_class.unicode_for_glyph_name("")

      expect(result).to be_nil
    end
  end

  describe ".agl_include?" do
    it "returns true for glyph in AGL" do
      expect(described_class.agl_include?("A")).to be true
      expect(described_class.agl_include?("space")).to be true
    end

    it "returns false for glyph not in AGL" do
      expect(described_class.agl_include?("not_a_real_glyph")).to be false
    end
  end

  describe ".generate_uni_name" do
    it "generates uniXXXX name for codepoint" do
      result = described_class.generate_uni_name(0x1234)

      expect(result).to eq("uni1234")
    end

    it "pads to 4 hex digits" do
      result = described_class.generate_uni_name(0xAB)

      expect(result).to eq("uni00AB")
    end
  end

  describe ".parse_uni_name" do
    it "parses uniXXXX format" do
      result = described_class.parse_uni_name("uni1234")

      expect(result).to eq(0x1234)
    end

    it "parses uXXXXX format" do
      result = described_class.parse_uni_name("u12345")

      expect(result).to eq(0x12345)
    end

    it "returns nil for non-uni name" do
      result = described_class.parse_uni_name("A")

      expect(result).to be_nil
    end

    it "returns nil for empty string" do
      result = described_class.parse_uni_name("")

      expect(result).to be_nil
    end

    it "returns nil for malformed uni name" do
      result = described_class.parse_uni_name("uniZZZZ")

      expect(result).to be_nil
    end
  end

  describe ".all_glyph_names" do
    it "returns all glyph names in AGL subset" do
      names = described_class.all_glyph_names

      expect(names).to be_an(Array)
      expect(names).to include("A")
      expect(names).to include("a")
      expect(names).to include("space")
      expect(names).to include("Agrave")
    end

    it "returns sorted names" do
      names = described_class.all_glyph_names

      expect(names).to eq(names.sort)
    end
  end

  describe ".all_codepoints" do
    it "returns all codepoints in AGL subset" do
      codepoints = described_class.all_codepoints

      expect(codepoints).to be_an(Array)
      expect(codepoints).to include(0x0020) # space
      expect(codepoints).to include(0x0041) # A
      expect(codepoints).to include(0x00C0) # Agrave
    end

    it "returns sorted codepoints" do
      codepoints = described_class.all_codepoints

      expect(codepoints).to eq(codepoints.sort)
    end
  end
end
