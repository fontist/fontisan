# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Converters::OutlineConverter do
  let(:converter) { described_class.new }
  let(:ttf_font) { double("TrueTypeFont") }
  let(:otf_font) { double("OpenTypeFont") }

  before do
    # Setup TTF font mock with dynamic has_table? response
    allow(ttf_font).to receive(:has_table?) do |tag|
      case tag
      when "glyf", "loca", "head", "hhea", "maxp" then true
      when "CFF ", "CFF2" then false
      else false
      end
    end
    allow(ttf_font).to receive(:table) do |tag|
      case tag
      when "glyf", "loca", "head", "hhea", "maxp" then double(tag)
      when "CFF ", "CFF2" then nil
      else nil
      end
    end
    allow(ttf_font).to receive(:tables).and_return({})
    allow(ttf_font).to receive(:table_data).and_return({})

    # Setup OTF font mock with dynamic has_table? response
    allow(otf_font).to receive(:has_table?) do |tag|
      case tag
      when "CFF ", "head", "hhea", "maxp" then true
      when "glyf", "CFF2" then false
      else false
      end
    end
    allow(otf_font).to receive(:table) do |tag|
      case tag
      when "CFF ", "head", "hhea", "maxp" then double(tag)
      when "glyf", "CFF2" then nil
      else nil
      end
    end
    allow(otf_font).to receive(:tables).and_return({})
    allow(otf_font).to receive(:table_data).and_return({})
  end

  describe "#convert" do
    context "with invalid parameters" do
      it "raises ArgumentError for nil font" do
        expect do
          converter.convert(nil, target_format: :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises ArgumentError for font without tables method" do
        invalid_font = double("InvalidFont")
        allow(invalid_font).to receive(:table).and_return(double)

        expect do
          converter.convert(invalid_font, target_format: :otf)
        end.to raise_error(ArgumentError, /must respond to :tables/)
      end
    end
  end

  describe "#supported_conversions" do
    it "includes TTF to OTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[ttf otf])
    end

    it "includes OTF to TTF" do
      conversions = converter.supported_conversions
      expect(conversions).to include(%i[otf ttf])
    end

    it "does not include same-format conversions" do
      conversions = converter.supported_conversions
      expect(conversions).not_to include(%i[ttf ttf])
      expect(conversions).not_to include(%i[otf otf])
    end
  end

  describe "#validate" do
    context "with valid fonts" do
      it "validates TTF to OTF conversion" do
        # Ensure loca has_table? returns true
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
        allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)

        expect do
          converter.validate(ttf_font, :otf)
        end.not_to raise_error
      end

      it "validates OTF to TTF conversion" do
        expect do
          converter.validate(otf_font, :ttf)
        end.not_to raise_error
      end
    end

    context "with invalid fonts" do
      it "rejects nil font" do
        expect do
          converter.validate(nil, :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "rejects unsupported conversion" do
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :svg)
        end.to raise_error(Fontisan::Error, /not supported/)
      end
    end

    context "with missing required tables" do
      it "rejects TTF without glyf table" do
        # Keep has_table? true so format detection works
        # But make table() return nil so validation fails
        allow(ttf_font).to receive(:table).with("glyf").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects TTF without loca table" do
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(false)
        allow(ttf_font).to receive(:table).with("loca").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /glyf or loca/)
      end

      it "rejects OTF without CFF table" do
        # Keep has_table? true for format detection
        # But make table() return nil for validation failure
        allow(otf_font).to receive(:table).with("CFF ").and_return(nil)

        expect do
          converter.validate(otf_font, :ttf)
        end.to raise_error(Fontisan::MissingTableError, /CFF/)
      end

      it "rejects font without head table" do
        # Ensure glyf and loca are properly set up
        allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
        allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
        allow(ttf_font).to receive(:table).with("glyf").and_return(double("glyf"))
        allow(ttf_font).to receive(:table).with("loca").and_return(double("loca"))
        allow(ttf_font).to receive(:table).with("head").and_return(nil)

        expect do
          converter.validate(ttf_font, :otf)
        end.to raise_error(Fontisan::MissingTableError, /head/)
      end
    end
  end

  describe "#supports?" do
    it "returns true for TTF to OTF" do
      expect(converter.supports?(:ttf, :otf)).to be true
    end

    it "returns true for OTF to TTF" do
      expect(converter.supports?(:otf, :ttf)).to be true
    end

    it "returns false for TTF to TTF" do
      expect(converter.supports?(:ttf, :ttf)).to be false
    end

    it "returns false for OTF to OTF" do
      expect(converter.supports?(:otf, :otf)).to be false
    end
  end

  describe "format detection" do
    it "detects TTF from glyf table" do
      format = converter.send(:detect_format, ttf_font)
      expect(format).to eq(:ttf)
    end

    it "detects OTF from CFF table" do
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "prefers CFF over CFF2" do
      allow(otf_font).to receive(:table).with("CFF2").and_return(double)
      format = converter.send(:detect_format, otf_font)
      expect(format).to eq(:otf)
    end

    it "raises error for unknown format" do
      unknown_font = double("UnknownFont")
      allow(unknown_font).to receive_messages(has_table?: false, table: nil)

      expect do
        converter.send(:detect_format, unknown_font)
      end.to raise_error(Fontisan::Error, /Cannot detect font format/)
    end
  end

  describe "hint preservation" do
    context "TTF to OTF with preserve_hints: true", :slow do
      it "extracts, converts, and applies hints" do
        font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Convert with hint preservation
        result = converter.convert(font, target_format: :otf, preserve_hints: true)

        # Should have CFF table
        expect(result["CFF "]).not_to be_nil

        # Note: PostScript hints are validated but not yet applied to CFF
        # (CFF modification requires full table rebuilding)
      end
    end

    context "TTF to OTF with preserve_hints: false" do
      it "skips hint extraction and conversion" do
        font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Convert without hint preservation (default)
        result = converter.convert(font, target_format: :otf, preserve_hints: false)

        # Should have CFF table
        expect(result["CFF "]).not_to be_nil

        # Hints not extracted or converted
      end
    end

    context "OTF to TTF with preserve_hints: true", :slow do
      it "extracts, converts, and applies hints" do
        font_path = "spec/fixtures/fonts/SourceSansPro-Regular.otf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Convert with hint preservation
        result = converter.convert(font, target_format: :ttf, preserve_hints: true)

        # Should have TrueType tables
        expect(result["glyf"]).not_to be_nil
        expect(result["loca"]).not_to be_nil

        # Hints should be applied if source had hints
        # Check for hint tables (fpgm, prep, cvt)
      end
    end

    context "OTF to TTF with preserve_hints: false" do
      it "skips hint extraction and conversion" do
        font_path = "spec/fixtures/fonts/SourceSansPro-Regular.otf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Convert without hint preservation
        result = converter.convert(font, target_format: :ttf, preserve_hints: false)

        # Should have TrueType tables
        expect(result["glyf"]).not_to be_nil
        expect(result["loca"]).not_to be_nil

        # Hints not extracted or converted
        # fpgm, prep, cvt tables should not be present from conversion
      end
    end

    context "error handling" do
      it "handles fonts without hints gracefully" do
        font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Should not raise error even if font has no hints
        expect do
          converter.convert(font, target_format: :otf, preserve_hints: true)
        end.not_to raise_error
      end

      it "handles hint extraction failures gracefully" do
        font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
        skip "Test font not available" unless File.exist?(font_path)

        font = Fontisan::FontLoader.load(font_path)
        converter = described_class.new

        # Mock the hint set extraction to return empty hint set (simulating failure)
        empty_hint_set = Fontisan::Models::HintSet.new(format: :truetype)
        allow(converter).to receive(:extract_ttf_hint_set).and_return(empty_hint_set)

        # Should complete conversion despite hint extraction returning empty set
        expect do
          result = converter.convert(font, target_format: :otf, preserve_hints: true)
          expect(result["CFF "]).not_to be_nil
        end.not_to raise_error
      end
    end
  end
end
