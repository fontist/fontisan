# frozen_string_literal: true

RSpec.describe Fontisan::Type1::Encodings do
  describe "AdobeStandard" do
    let(:encoding) { described_class::AdobeStandard }

    describe ".glyph_name_for_code" do
      it "returns glyph name for ASCII character" do
        # In Adobe Standard Encoding, 'A' is at position 34
        expect(encoding.glyph_name_for_code(34)).to eq("A")
      end

      it "returns glyph name for space" do
        # In Adobe Standard Encoding, 'space' is at position 1
        expect(encoding.glyph_name_for_code(1)).to eq("space")
      end

      it "returns glyph name for accented character" do
        # In Adobe Standard Encoding, 'Agrave' is at position 229
        expect(encoding.glyph_name_for_code(229)).to eq("Agrave")
      end

      it "returns nil for character not in encoding" do
        expect(encoding.glyph_name_for_code(256)).to be_nil
      end

      it "returns nil for control characters" do
        expect(encoding.glyph_name_for_code(0)).to be_nil
      end
    end

    describe ".codepoint_for_glyph" do
      it "returns codepoint for glyph name" do
        # In Adobe Standard Encoding, 'A' is at position 34
        expect(encoding.codepoint_for_glyph("A")).to eq(34)
      end

      it "returns codepoint for space" do
        # In Adobe Standard Encoding, 'space' is at position 1
        expect(encoding.codepoint_for_glyph("space")).to eq(1)
      end

      it "returns codepoint for accented character" do
        # In Adobe Standard Encoding, 'Agrave' is at position 229
        expect(encoding.codepoint_for_glyph("Agrave")).to eq(229)
      end

      it "returns nil for unknown glyph" do
        expect(encoding.codepoint_for_glyph("unknown")).to be_nil
      end
    end

    describe ".include?" do
      it "returns true for glyph in encoding" do
        expect(encoding.include?("A")).to be true
      end

      it "returns false for glyph not in encoding" do
        expect(encoding.include?("unknown")).to be false
      end
    end

    describe ".encoding_name" do
      it "returns encoding name" do
        expect(encoding.encoding_name).to eq("AdobeStandard")
      end
    end

    describe ".all_glyph_names" do
      it "returns all glyph names in encoding" do
        names = encoding.all_glyph_names

        expect(names).to include("A")
        expect(names).to include("space")
        expect(names).to include("Agrave")
        expect(names).not_to include(".notdef")
      end
    end
  end

  describe "ISOLatin1" do
    let(:encoding) { described_class::ISOLatin1 }

    describe ".glyph_name_for_code" do
      it "returns glyph name for ASCII character" do
        # In this implementation, 'A' is at position 34
        expect(encoding.glyph_name_for_code(34)).to eq("A")
      end

      it "returns glyph name for Latin-1 supplement" do
        # In this implementation, 'Agrave' is at position 160
        expect(encoding.glyph_name_for_code(160)).to eq("Agrave")
        expect(encoding.glyph_name_for_code(137)).to eq("copyright")
      end

      it "returns nil for character not in encoding" do
        expect(encoding.glyph_name_for_code(256)).to be_nil
      end
    end

    describe ".codepoint_for_glyph" do
      it "returns codepoint for glyph name" do
        # In this implementation, 'A' is at position 34
        expect(encoding.codepoint_for_glyph("A")).to eq(34)
      end

      it "returns codepoint for Latin-1 glyph" do
        # In this implementation, 'copyright' is at position 137
        expect(encoding.codepoint_for_glyph("copyright")).to eq(137)
      end
    end

    describe ".encoding_name" do
      it "returns encoding name" do
        expect(encoding.encoding_name).to eq("ISOLatin1")
      end
    end
  end

  describe "Unicode" do
    let(:encoding) { described_class::Unicode }

    describe ".glyph_name_for_code" do
      it "returns AGL glyph name for common character" do
        expect(encoding.glyph_name_for_code(65)).to eq("A")
      end

      it "returns uniXXXX name for character not in AGL" do
        result = encoding.glyph_name_for_code(0x1234)

        expect(result).to eq("uni1234")
      end

      it "returns uniXXXX with 4 hex digits for BMP" do
        result = encoding.glyph_name_for_code(0xABCD)

        expect(result).to eq("uniABCD")
      end
    end

    describe ".codepoint_for_glyph" do
      it "returns codepoint for AGL glyph name" do
        expect(encoding.codepoint_for_glyph("A")).to eq(65)
      end

      it "returns codepoint for uniXXXX name" do
        result = encoding.codepoint_for_glyph("uni1234")

        expect(result).to eq(0x1234)
      end

      it "returns nil for unknown glyph name" do
        expect(encoding.codepoint_for_glyph("unknown")).to be_nil
      end
    end

    describe ".include?" do
      it "always returns true for Unicode encoding" do
        expect(encoding.include?("any_glyph")).to be true
      end
    end

    describe ".encoding_name" do
      it "returns encoding name" do
        expect(encoding.encoding_name).to eq("Unicode")
      end
    end
  end
end
