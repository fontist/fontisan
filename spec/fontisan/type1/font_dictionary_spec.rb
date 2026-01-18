# frozen_string_literal: true

RSpec.describe Fontisan::Type1::FontDictionary do
  describe "#initialize" do
    it "creates a new FontDictionary" do
      dict = described_class.new

      expect(dict.font_info).to be_a(Fontisan::Type1::FontDictionary::FontInfo)
      expect(dict.encoding).to be_a(Fontisan::Type1::FontDictionary::Encoding)
      expect(dict.raw_data).to eq({})
    end
  end

  describe ".parse" do
    it "parses font dictionary from data with FontName" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont
        /FontName /TestFont def
      DATA

      dict = described_class.parse(data)

      expect(dict.font_name).to eq("TestFont")
    end

    it "parses FontBBox" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        /FontBBox {-100 -200 500 600} def
      DATA

      dict = described_class.parse(data)

      expect(dict.font_b_box).to eq([-100, -200, 500, 600])
    end

    it "parses FontBBox with array syntax" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        /FontBBox [0 0 1000 1000] def
      DATA

      dict = described_class.parse(data)

      expect(dict.font_b_box).to eq([0, 0, 1000, 1000])
    end

    it "defaults FontBBox if not found" do
      data = "%!PS-AdobeFont-1.0"

      dict = described_class.parse(data)

      expect(dict.font_b_box).to eq([0, 0, 0, 0])
    end

    it "parses FontMatrix" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        /FontMatrix [0.001 0 0 0.001 0 0] def
      DATA

      dict = described_class.parse(data)

      expect(dict.font_matrix).to eq([0.001, 0, 0, 0.001, 0, 0])
    end

    it "defaults FontMatrix if not found" do
      data = "%!PS-AdobeFont-1.0"

      dict = described_class.parse(data)

      expect(dict.font_matrix).to eq([0.001, 0, 0, 0.001, 0, 0])
    end

    it "parses PaintType" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        /PaintType 0 def
      DATA

      dict = described_class.parse(data)

      expect(dict.paint_type).to eq(0)
    end

    it "defaults PaintType if not found" do
      data = "%!PS-AdobeFont-1.0"

      dict = described_class.parse(data)

      expect(dict.paint_type).to eq(0)
    end

    it "returns self for method chaining" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new

      result = dict.parse(data)

      expect(result).to be(dict)
    end
  end

  describe "#parsed?" do
    it "returns false before parsing" do
      dict = described_class.new

      expect(dict.parsed?).to be false
    end

    it "returns true after parsing" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new.parse(data)

      expect(dict.parsed?).to be true
    end
  end

  describe "#[]" do
    it "returns nil for unknown key" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new.parse(data)

      expect(dict[:unknown_key]).to be_nil
    end

    it "returns value for known key" do
      data = <<~DATA
        /FontName /TestFont def
      DATA

      dict = described_class.new.parse(data)

      expect(dict[:font_name]).to eq("TestFont")
    end
  end

  describe "FontInfo" do
    it "parses FullName" do
      <<~DATA
        /FullName (Test Font Regular) def
      DATA

      dict = described_class.new
      dict.font_info.parse({ full_name: "Test Font Regular" })

      expect(dict.font_info.full_name).to eq("Test Font Regular")
    end

    it "parses FamilyName" do
      dict = described_class.new
      dict.font_info.parse({ family_name: "Test Family" })

      expect(dict.font_info.family_name).to eq("Test Family")
    end

    it "parses version" do
      dict = described_class.new
      dict.font_info.parse({ version: "001.000" })

      expect(dict.font_info.version).to eq("001.000")
    end

    it "handles nil values" do
      dict = described_class.new

      expect(dict.font_info.full_name).to be_nil
      expect(dict.font_info.family_name).to be_nil
    end
  end

  describe "Encoding" do
    it "defaults to standard encoding" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new.parse(data)

      expect(dict.encoding.standard?).to be true
    end

    it "maps common ASCII characters" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new.parse(data)

      expect(dict.encoding[65]).to eq("A")  # 'A'
      expect(dict.encoding[97]).to eq("a")  # 'a'
      expect(dict.encoding[32]).to eq("space")
    end

    it "returns nil for unknown character codes" do
      data = "%!PS-AdobeFont-1.0"
      dict = described_class.new.parse(data)

      expect(dict.encoding[999]).to be_nil
    end
  end
end
