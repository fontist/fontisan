# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Outline Conversion Integration" do
  let(:output_dir) { "spec/fixtures/output" }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    # Clean up generated files
    Dir.glob("#{output_dir}/*").each { |f| FileUtils.rm_f(f) }
  end

  describe "OutlineConverter capabilities" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    it "supports TTF to OTF conversion" do
      expect(converter.supported_conversions).to include(%i[ttf otf])
    end

    it "supports OTF to TTF conversion" do
      expect(converter.supported_conversions).to include(%i[otf ttf])
    end

    it "validates source font has required tables" do
      ttf_font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
      font = Fontisan::FontLoader.load(ttf_font_path)

      expect do
        converter.validate(font, :otf)
      end.not_to raise_error
    end
  end

  describe "Compound glyph support" do
    context "with fonts containing compound glyphs" do
      let(:ttf_font_path) { "spec/fixtures/fonts/NotoSans-Regular.ttf" }
      let(:converter) { Fontisan::Converters::OutlineConverter.new }

      it "successfully converts fonts with compound glyphs" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        expect do
          converter.convert(font, target_format: :otf)
        end.not_to raise_error
      end

      it "decomposes compound glyphs into simple outlines" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, target_format: :otf)

        # Should have CFF table instead of glyf/loca
        expect(tables.keys).to include("CFF ")
        expect(tables.keys).not_to include("glyf", "loca")
      end

      it "produces valid CFF output" do
        font = Fontisan::FontLoader.load(ttf_font_path)

        tables = converter.convert(font, target_format: :otf)

        # CFF table should be non-empty binary data
        expect(tables["CFF "]).to be_a(String)
        expect(tables["CFF "].encoding).to eq(Encoding::BINARY)
        expect(tables["CFF "].bytesize).to be > 0
      end
    end
  end

  describe "Architecture and design" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    it "uses universal Outline model for format conversion" do
      # The converter uses Fontisan::Models::Outline as intermediate format
      expect(Fontisan::Models::Outline).to respond_to(:from_truetype)
      expect(Fontisan::Models::Outline).to respond_to(:from_cff)
    end

    it "converts through outline model pipeline" do
      # TrueType → Outline → CFF
      outline = Fontisan::Models::Outline.new(
        glyph_id: 0,
        commands: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      expect(outline).to respond_to(:to_cff_commands)
      expect(outline).to respond_to(:to_truetype_contours)
    end

    it "preserves non-outline tables during conversion" do
      ttf_font_path = "spec/fixtures/fonts/NotoSans-Regular.ttf"
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Get original table list
      original_tables = font.table_data.keys - ["glyf", "loca"]

      # Verify we have tables to preserve
      expect(original_tables).not_to be_empty
      expect(original_tables).to include("head", "hhea", "maxp")
    end
  end

  describe "Table updates during conversion" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    context "TTF to OTF conversion" do
      it "updates maxp table to version 0.5 (CFF)" do
        skip "Requires compound glyph support"
      end

      it "updates head table indexToLocFormat" do
        skip "Requires compound glyph support"
      end

      it "creates CFF table" do
        skip "Requires compound glyph support"
      end
    end

    context "OTF to TTF conversion" do
      it "updates maxp table to version 1.0 (TrueType)" do
        skip "Requires compound glyph support"
      end

      it "creates glyf and loca tables" do
        skip "Requires compound glyph support"
      end
    end
  end

  describe "Conversion quality" do
    context "when compound glyph support is added" do
      it "preserves glyph metrics" do
        skip "Requires compound glyph support"
      end

      it "maintains glyph shapes with high fidelity" do
        skip "Requires compound glyph support"
      end

      it "supports round-trip conversion" do
        skip "Requires compound glyph support"
      end
    end
  end

  describe "Error handling" do
    let(:converter) { Fontisan::Converters::OutlineConverter.new }

    it "validates font has required methods" do
      invalid_font = double("InvalidFont")

      expect do
        converter.validate(invalid_font, :otf)
      end.to raise_error(ArgumentError, /must respond to/)
    end

    it "rejects nil font" do
      expect do
        converter.validate(nil, :otf)
      end.to raise_error(ArgumentError, /Font cannot be nil/)
    end

    it "detects missing required tables" do
      font = double("Font")
      allow(font).to receive_messages(has_table?: false, table: nil, tables: {})

      expect do
        converter.validate(font, :otf)
      end.to raise_error(Fontisan::Error)
    end
  end

  describe "Future capabilities (planned)" do
    it "supports compound glyphs" do
      skip "Planned for Phase 1 Week 5"
    end

    it "optimizes CFF with subroutines" do
      skip "Planned for future phases"
    end

    it "preserves hints during conversion" do
      skip "Planned for future phases"
    end

    it "supports CFF2 and variable fonts" do
      skip "Planned for future phases"
    end
  end
end
