# frozen_string_literal: true

RSpec.describe Fontisan::Type1Font, "with real Type 1 fonts" do
  describe "loading PFB format" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:font) do
      f = Fontisan::FontLoader.load(pfb_path)
      f.parse_dictionaries!
      f
    end

    it "loads PFB file successfully" do
      expect(font).to be_a(described_class)
    end

    it "extracts font name from PFB" do
      expect(font.font_name).to eq("Bfont")
    end

    it "has font dictionary" do
      expect(font.font_dictionary).to be_a(Fontisan::Type1::FontDictionary)
    end

    it "has private dictionary" do
      expect(font.private_dict).to be_a(Fontisan::Type1::PrivateDict)
    end

    it "has charstrings" do
      expect(font.charstrings).to be_a(Fontisan::Type1::CharStrings)
      expect(font.charstrings.count).to be > 0
    end

    it "has decrypted data available" do
      expect(font.decrypted?).to be true
      expect(font.decrypted_data).not_to be_empty
    end

    it "provides font metrics" do
      expect(font.font_dictionary.font_bbox).to be_a(Array)
      expect(font.font_dictionary.font_bbox.length).to eq(4)
    end
  end

  describe "loading PFB format - validation" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:font) do
      f = Fontisan::FontLoader.load(pfb_path)
      f.parse_dictionaries!
      f
    end

    it "provides full name" do
      expect(font.font_dictionary.full_name).to eq("Bfont")
    end

    it "provides family name" do
      expect(font.font_dictionary.family_name).to eq("Bfont")
    end

    it "has font matrix" do
      expect(font.font_dictionary.font_matrix).to be_a(Array)
      expect(font.font_dictionary.font_matrix.length).to eq(6)
    end

    it "has version" do
      expect(font.font_dictionary.version).to eq("001.001")
    end
  end

  describe "format detection consistency" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:font) do
      f = Fontisan::FontLoader.load(pfb_path)
      f.parse_dictionaries!
      f
    end

    it "loads consistently" do
      expect(font.font_dictionary).to be_a(Fontisan::Type1::FontDictionary)
      expect(font.charstrings.count).to be > 0
    end
  end

  describe "CharString access with real fonts" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:font) do
      f = Fontisan::FontLoader.load(pfb_path)
      f.parse_dictionaries!
      f
    end

    it "can iterate over all charstrings" do
      count = 0
      font.charstrings.each_charstring do |name, data|
        expect(name).to be_a(String)
        expect(data).to be_a(String)
        count += 1
      end
      expect(count).to eq(font.charstrings.count)
    end

    it "can get charstring data by name" do
      # Get first glyph name
      first_glyph = font.charstrings.glyph_names.first
      data = font.charstrings.charstring(first_glyph)
      expect(data).to be_a(String)
    end
  end

  describe "Type1Converter with real fonts" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:converter) { Fontisan::Converters::Type1Converter.new }
    let(:output_dir) { File.expand_path("../fixtures/output", __dir__) }

    before do
      FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
    end

    describe "Type 1 to OTF conversion" do
      it "converts PFB to OTF" do
        font = Fontisan::FontLoader.load(pfb_path)
        font.parse_dictionaries!
        expect do
          converter.convert(font, target_format: :otf)
        end.not_to raise_error
      end
    end

    describe "Type1Converter validation" do
      it "validates Type1Font can be converted to OTF" do
        font = Fontisan::FontLoader.load(pfb_path)
        font.parse_dictionaries!
        expect { converter.validate(font, :otf) }.not_to raise_error
      end

      it "reports supported conversions" do
        conversions = converter.supported_conversions
        expect(conversions).to include(%i[type1 otf])
        expect(conversions).to include(%i[otf type1])
      end
    end
  end

  describe "CharStringConverter with real fonts" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end
    let(:font) do
      f = Fontisan::FontLoader.load(pfb_path)
      f.parse_dictionaries!
      f
    end
    let(:converter) { Fontisan::Type1::CharStringConverter.new(font.charstrings) }

    it "can convert Type 1 charstrings to CFF" do
      font.charstrings.each_charstring do |_glyph_name, type1_cs|
        cff_cs = converter.convert(type1_cs)
        expect(cff_cs).to be_a(String)
      end
    end

    it "detects seac composites if present" do
      font.charstrings.each_charstring do |_glyph_name, type1_cs|
        is_seac = converter.seac?(type1_cs)
        # Just check the method works - seac may or may not be present
        expect([true, false]).to include(is_seac)
      end
    end
  end

  describe "AFM file support" do
    let(:afm_path) do
      File.expand_path("../fixtures/fonts/type1/matrix.afm", __dir__)
    end

    it "AFM file exists for reference" do
      expect(File.exist?(afm_path)).to be true
    end

    it "contains valid AFM data" do
      content = File.read(afm_path)
      expect(content).to start_with("StartFontMetrics")
      expect(content).to include("FontName")
      expect(content).to include("EncodingScheme")
    end
  end

  describe "Format detection with real fonts" do
    let(:pfb_path) do
      File.expand_path("../fixtures/fonts/type1/quicksand.pfb", __dir__)
    end

    it "detects PFB as Type 1 format" do
      expect(Fontisan::FontLoader.collection?(pfb_path)).to be false
      # Loading should succeed and return Type1Font
      font = Fontisan::FontLoader.load(pfb_path)
      expect(font).to be_a(described_class)
    end
  end
end
