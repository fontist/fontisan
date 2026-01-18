# frozen_string_literal: true

RSpec.describe Fontisan::Type1::Generator do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }

  describe ".generate" do
    it "generates all Type 1 formats with default options" do
      result = described_class.generate(font)

      expect(result).to be_a(Hash)
      expect(result.keys).to include(:afm, :pfm, :pfb, :inf)
      expect(result.keys).not_to include(:pfa) # Default is PFB
    end

    it "generates AFM content" do
      result = described_class.generate(font)

      expect(result[:afm]).to be_a(String)
      expect(result[:afm]).to start_with("StartFontMetrics")
      expect(result[:afm]).to include("FontName")
    end

    it "generates PFM content" do
      result = described_class.generate(font)

      expect(result[:pfm]).to be_a(String)
      # PFM should be binary
      expect(result[:pfm].encoding.name).to eq("ASCII-8BIT")
    end

    it "generates PFB content by default" do
      result = described_class.generate(font)

      expect(result[:pfb]).to be_a(String)
      expect(result.keys).not_to include(:pfa)
    end

    it "generates PFA content when format is :pfa" do
      result = described_class.generate(font, format: :pfa)

      expect(result[:pfa]).to be_a(String)
      expect(result.keys).not_to include(:pfb)
    end

    it "generates INF content" do
      result = described_class.generate(font)

      expect(result[:inf]).to be_a(String)
      expect(result[:inf]).to include("[Font Description]")
      expect(result[:inf]).to include("[Files]")
    end

    it "accepts ConversionOptions" do
      options = Fontisan::Type1::ConversionOptions.unix_type1
      result = described_class.generate(font, options)

      expect(result[:pfa]).to be_a(String)
      expect(result.keys).not_to include(:pfb)
    end

    it "accepts hash options" do
      result = described_class.generate(font, upm_scale: 1000)

      expect(result[:afm]).to be_a(String)
    end

    it "applies UPM scaling when specified" do
      # Use a different scale value than the font's native UPM
      # If font has 1000 UPM, use 500 to ensure scaling occurs
      target_scale = font.units_per_em == 1000 ? 500 : 1000
      result_with_scaling = described_class.generate(font,
                                                     upm_scale: target_scale)
      result_native = described_class.generate(font, upm_scale: :native)

      # Font bounding box should be different
      expect(result_with_scaling[:afm]).not_to eq(result_native[:afm])
    end
  end

  describe ".generate_to_files" do
    let(:output_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(output_dir)
    end

    it "writes all generated files to disk" do
      files = described_class.generate_to_files(font, output_dir)

      expect(files.length).to be >= 4
      expect(files.any? { |f| f.end_with?(".afm") }).to be true
      expect(files.any? { |f| f.end_with?(".pfm") }).to be true
      expect(files.any? { |f| f.end_with?(".pfb") }).to be true
      expect(files.any? { |f| f.end_with?(".inf") }).to be true
    end

    it "creates output directory if it doesn't exist" do
      new_dir = File.join(output_dir, "subdir", "fonts")

      expect do
        described_class.generate_to_files(font, new_dir)
      end.not_to raise_error

      expect(Dir.exist?(new_dir)).to be true
    end

    it "writes PFA when format is :pfa" do
      files = described_class.generate_to_files(font, output_dir, format: :pfa)

      expect(files.any? { |f| f.end_with?(".pfa") }).to be true
      expect(files.any? { |f| f.end_with?(".pfb") }).to be false
    end

    it "returns array of file paths" do
      files = described_class.generate_to_files(font, output_dir)

      expect(files).to be_an(Array)
      expect(files).not_to be_empty
      expect(files.all? { |f| File.exist?(f) }).to be true
    end
  end

  describe "#initialize" do
    it "sets up scaler with options" do
      generator = described_class.new(font, upm_scale: 500)

      expect(generator.instance_variable_get(:@scaler).target_upm).to eq(500)
    end

    it "sets up encoding with options" do
      encoding = Fontisan::Type1::Encodings::Unicode
      generator = described_class.new(font, encoding: encoding)

      expect(generator.instance_variable_get(:@encoding)).to eq(encoding)
    end
  end

  describe "#generate" do
    it "generates all Type 1 formats" do
      generator = described_class.new(font)
      result = generator.generate

      expect(result.keys).to include(:afm, :pfm, :pfb, :inf)
    end

    it "respects format option" do
      generator = described_class.new(font, format: :pfa)
      result = generator.generate

      expect(result.keys).to include(:pfa)
      expect(result.keys).not_to include(:pfb)
    end
  end

  context "with URW Base35 font" do
    let(:font_path) { font_fixture_path("URWBase35", "C059-Bold.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }

    it "generates valid AFM with 1000 UPM scaling" do
      result = described_class.generate(font, upm_scale: 1000)

      afm = result[:afm]
      expect(afm).to start_with("StartFontMetrics")

      # Parse to verify
      parsed_afm = Fontisan::Type1::AFMParser.parse_string(afm)
      expect(parsed_afm.font_name).not_to be_nil
    end

    it "generates valid PFM with 1000 UPM scaling" do
      result = described_class.generate(font, upm_scale: 1000)

      pfm = result[:pfm]
      expect(pfm.bytesize).to be > 0

      # Parse to verify
      parsed_pfm = Fontisan::Type1::PFMParser.parse_string(pfm)
      expect(parsed_pfm.font_name).not_to be_nil
    end
  end
end
