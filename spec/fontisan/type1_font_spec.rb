# frozen_string_literal: true

RSpec.describe Fontisan::Type1Font do
  describe ".from_file" do
    context "with valid Type1 file" do
      it "returns a Type1Font instance" do
        type1_path = fixture_path("fonts/type1/quicksand.pfb")
        font = described_class.from_file(type1_path)

        expect(font).to be_a(described_class)
      end

      it "sets the loading mode correctly" do
        type1_path = fixture_path("fonts/type1/quicksand.pfb")
        font = described_class.from_file(type1_path, mode: :metadata)

        expect(font.loading_mode).to eq(:metadata)
      end
    end

    context "with invalid inputs" do
      it "raises ArgumentError for nil file path" do
        expect { described_class.from_file(nil) }
          .to raise_error(ArgumentError, /File path cannot be nil/)
      end

      it "raises Error for non-existent file" do
        expect { described_class.from_file("/nonexistent/file.pfb") }
          .to raise_error(Fontisan::Error, /File not found/)
      end
    end
  end

  describe "#initialize" do
    it "auto-detects PFB format" do
      data = "\x80\x01\x04\x00\x00\x00test\x80\x03"
      font = described_class.new(data)

      expect(font.format).to eq(:pfb)
    end

    it "auto-detects PFA format" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data)

      expect(font.format).to eq(:pfa)
    end

    it "accepts explicit format" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data, format: :pfa)

      expect(font.format).to eq(:pfa)
    end

    it "raises Error for unrecognizable format" do
      expect { described_class.new("random data") }
        .to raise_error(Fontisan::Error, /Cannot detect Type 1 format/)
    end

    it "stores file path when provided" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data, file_path: "/path/to/font.pfa")

      expect(font.file_path).to eq("/path/to/font.pfa")
    end
  end

  describe "#clear_text" do
    it "returns clear text for PFB format" do
      data = "\x80\x01\x05\x00\x00\x00Hello\x80\x03"
      font = described_class.new(data)

      expect(font.clear_text).to eq("Hello")
    end

    it "returns clear text for PFA format" do
      data = "%!PS-AdobeFont-1.0: TestFont 1.0\n% Clear text portion"
      font = described_class.new(data)

      expect(font.clear_text).to include("%!PS-AdobeFont-1.0")
    end
  end

  describe "#encrypted?" do
    it "returns true for PFB with binary chunks" do
      data = "\x80\x01\x04\x00\x00\x00test\x80\x02\x04\x00\x00\x00bin\x00\x80\x03"
      font = described_class.new(data)

      expect(font).to be_encrypted
    end

    it "returns true for PFA with eexec marker" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont
        currentfile eexec
        encrypted
        #{'0' * 512}
      DATA

      font = described_class.new(data)
      expect(font).to be_encrypted
    end

    it "returns false for PFA without eexec" do
      data = "%!PS-AdobeFont-1.0: TestFont\n/all clear"
      font = described_class.new(data)

      expect(font).not_to be_encrypted
    end
  end

  describe "#decrypted?" do
    it "returns false before decryption" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data)

      expect(font).not_to be_decrypted
    end

    it "returns true after decryption" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data)
      font.decrypt!

      expect(font).to be_decrypted
    end
  end

  describe "#decrypt!" do
    it "returns cached decrypted data if already decrypted" do
      data = "%!PS-AdobeFont-1.0: TestFont"
      font = described_class.new(data)

      result1 = font.decrypt!
      result2 = font.decrypt!

      expect(result1).to be(result2)
    end

    it "returns clear text if not encrypted" do
      data = "%!PS-AdobeFont-1.0: TestFont\n/all clear"
      font = described_class.new(data)

      decrypted = font.decrypt!

      expect(decrypted).to include("%!PS-AdobeFont-1.0")
    end
  end

  describe "#font_name" do
    it "extracts FontName from dictionary" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont 1.0
        /FontName /TestFont def
      DATA

      font = described_class.new(data)
      expect(font.font_name).to eq("TestFont")
    end

    it "returns nil if FontName not found" do
      data = "%!PS-AdobeFont-1.0: TestFont\n/no fontname here/"

      font = described_class.new(data)
      expect(font.font_name).to be_nil
    end
  end

  describe "#full_name" do
    it "extracts FullName from FontInfo" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont 1.0
        /FontInfo 10 dict dup begin
          (FullName) readonly (Test Font Regular) readonly
        end readonly def
      DATA

      font = described_class.new(data)
      expect(font.full_name).to eq("Test Font Regular")
    end

    it "returns nil if FullName not found" do
      data = "%!PS-AdobeFont-1.0: TestFont\n/no fullname/"

      font = described_class.new(data)
      expect(font.full_name).to be_nil
    end
  end

  describe "#family_name" do
    it "extracts FamilyName from FontInfo" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont 1.0
        /FontInfo 10 dict dup begin
          /FamilyName (Test Family) def
        end readonly def
      DATA

      font = described_class.new(data)
      expect(font.family_name).to eq("Test Family")
    end
  end

  describe "#version" do
    it "extracts version from FontInfo" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont 1.0
        /FontInfo 10 dict dup begin
          /version (001.000) def
        end readonly def
      DATA

      font = described_class.new(data)
      expect(font.version).to eq("001.000")
    end
  end
end
