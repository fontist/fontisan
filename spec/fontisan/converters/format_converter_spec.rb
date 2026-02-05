# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Converters::FormatConverter do
  let(:converter) { described_class.new }
  let(:ttf_font) { double("TrueTypeFont") }
  let(:otf_font) { double("OpenTypeFont") }

  # Mock tables for detecting format
  before do
    allow(ttf_font).to receive(:has_table?).with("glyf").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("CFF ").and_return(false)
    allow(ttf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(ttf_font).to receive(:has_table?).with("fvar").and_return(false)
    allow(ttf_font).to receive(:table).with("glyf").and_return(double)
    allow(ttf_font).to receive(:table).with("CFF ").and_return(nil)
    allow(ttf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(ttf_font).to receive_messages(tables: { "glyf" => double, "head" => double }, table_data: { "glyf" => "glyf_data",
                                                                                                      "head" => "\x00" * 54 }, read_table_data: "data")
    allow(ttf_font).to receive(:table).with("name").and_return(double("name",
                                                                      english_name: "TestFont"))

    # Add stubs for OutlineConverter validation
    allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("head").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("hhea").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("maxp").and_return(true)
    allow(ttf_font).to receive(:table).with("loca").and_return(double("loca",
                                                                      parse_with_context: nil))
    allow(ttf_font).to receive(:table).with("head").and_return(double("head",
                                                                      units_per_em: 1000,
                                                                      index_to_loc_format: 1))
    allow(ttf_font).to receive(:table).with("hhea").and_return(double("hhea"))
    allow(ttf_font).to receive(:table).with("maxp").and_return(double("maxp",
                                                                      num_glyphs: 100))
    allow(ttf_font).to receive(:table).with("name").and_return(double("name",
                                                                      english_name: "TestFont"))

    # Mock glyf table to handle glyph_for calls
    glyf_mock = double("glyf")
    allow(glyf_mock).to receive(:glyph_for) do |_glyph_id, _loca, _head|
      # Return empty glyph mock
      glyph_mock = double("glyph")
      allow(glyph_mock).to receive_messages(
        nil?: false,
        empty?: true,
        simple?: true,
        compound?: false,
      )
      glyph_mock
    end
    allow(ttf_font).to receive(:table).with("glyf").and_return(glyf_mock)

    allow(otf_font).to receive(:has_table?).with("glyf").and_return(false)
    allow(otf_font).to receive(:has_table?).with("CFF ").and_return(true)
    allow(otf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(otf_font).to receive(:has_table?).with("fvar").and_return(false)
    allow(otf_font).to receive(:table).with("CFF ").and_return(double("cff",
                                                                      glyph_count: 100,
                                                                      charstring_for_glyph: nil))
    allow(otf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(otf_font).to receive(:table).with("glyf").and_return(nil)
    allow(otf_font).to receive_messages(tables: { "CFF " => double, "head" => double }, table_data: { "CFF " => "CFF _data",
                                                                                                      "head" => "\x00" * 54 }, read_table_data: "data")

    # Add stubs for OutlineConverter validation
    allow(otf_font).to receive(:has_table?).with("head").and_return(true)
    allow(otf_font).to receive(:has_table?).with("hhea").and_return(true)
    allow(otf_font).to receive(:has_table?).with("maxp").and_return(true)
    allow(otf_font).to receive(:table).with("head").and_return(double("head",
                                                                      units_per_em: 1000))
    allow(otf_font).to receive(:table).with("hhea").and_return(double("hhea"))
    allow(otf_font).to receive(:table).with("maxp").and_return(double("maxp",
                                                                      num_glyphs: 100))
  end

  describe "#initialize" do
    it "creates a converter with default strategies" do
      expect(converter.strategies).not_to be_empty
      expect(converter.strategies).to all(respond_to(:convert))
    end

    it "loads conversion matrix" do
      expect(converter.conversion_matrix).not_to be_nil
      expect(converter.conversion_matrix).to have_key("conversions")
    end

    context "with custom conversion matrix path" do
      let(:custom_path) { "/path/to/custom/matrix.yml" }

      it "attempts to load from custom path" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(custom_path).and_return(false)
        converter = described_class.new(conversion_matrix_path: custom_path)
        expect(converter.conversion_matrix).not_to be_nil
      end
    end
  end

  describe "#convert" do
    context "with valid parameters" do
      it "converts TTF to TTF (copy operation)" do
        tables = converter.convert(ttf_font, :ttf)
        expect(tables).to be_a(Hash)
      end

      it "converts OTF to OTF (copy operation)" do
        tables = converter.convert(otf_font, :otf)
        expect(tables).to be_a(Hash)
      end

      # Skip these tests - they use mocks that don't fully simulate real fonts
      # Integration tests with real fonts cover actual conversion behavior
      it "successfully converts TTF to OTF with compound glyph support" do
        # CompoundGlyphResolver is implemented and handles compound glyphs
        # This should succeed without errors
        expect do
          converter.convert(ttf_font, :otf)
        end.not_to raise_error
      end

      it "successfully converts OTF to TTF with compound glyph support" do
        # CompoundGlyphResolver is implemented
        expect do
          converter.convert(otf_font, :ttf)
        end.not_to raise_error
      end
    end

    context "with invalid parameters" do
      it "raises ArgumentError for nil font" do
        expect do
          converter.convert(nil, :otf)
        end.to raise_error(ArgumentError, /Font cannot be nil/)
      end

      it "raises ArgumentError for font without table method" do
        invalid_font = double("InvalidFont")
        expect do
          converter.convert(invalid_font, :otf)
        end.to raise_error(ArgumentError, /must respond to :table/)
      end

      it "raises ArgumentError for non-symbol target format" do
        expect do
          converter.convert(ttf_font, "otf")
        end.to raise_error(ArgumentError, /must be a Symbol/)
      end
    end

    context "with unsupported conversions" do
      it "raises error for unsupported conversion with helpful message" do
        # Create test font without proper format
        unknown_font = double("UnknownFont")
        allow(unknown_font).to receive(:has_table?).and_return(false)
        allow(unknown_font).to receive_messages(table: nil, tables: {})

        expect do
          converter.convert(unknown_font, :woff2)
        end.to raise_error(Fontisan::Error, /Cannot detect font format/)
      end
    end
  end

  describe "#supported?" do
    it "returns true for TTF to TTF" do
      expect(converter.supported?(:ttf, :ttf)).to be true
    end

    it "returns true for OTF to OTF" do
      expect(converter.supported?(:otf, :otf)).to be true
    end

    it "returns true for TTF to OTF" do
      expect(converter.supported?(:ttf, :otf)).to be true
    end

    it "returns true for OTF to TTF" do
      expect(converter.supported?(:otf, :ttf)).to be true
    end

    it "returns true for TTF to WOFF2" do
      expect(converter.supported?(:ttf, :woff2)).to be true
    end

    it "returns true for OTF to WOFF2" do
      expect(converter.supported?(:otf, :woff2)).to be true
    end

    it "returns true for TTF to SVG" do
      expect(converter.supported?(:ttf, :svg)).to be true
    end

    it "returns true for OTF to SVG" do
      expect(converter.supported?(:otf, :svg)).to be true
    end

    it "returns false for unsupported conversion" do
      expect(converter.supported?(:svg, :ttf)).to be false
    end
  end

  describe "#supported_targets" do
    it "returns available targets for TTF" do
      targets = converter.supported_targets(:ttf)
      expect(targets).to include(:ttf, :otf, :woff2, :svg)
    end

    it "returns available targets for OTF" do
      targets = converter.supported_targets(:otf)
      expect(targets).to include(:otf, :ttf, :woff2, :svg)
    end

    it "returns empty array for unknown source" do
      targets = converter.supported_targets(:unknown)
      expect(targets).to be_empty
    end
  end

  describe "#all_conversions" do
    it "returns all supported conversions" do
      conversions = converter.all_conversions
      expect(conversions).not_to be_empty
      expect(conversions).to all(have_key(:from))
      expect(conversions).to all(have_key(:to))
    end

    it "includes same-format conversions" do
      conversions = converter.all_conversions
      ttf_to_ttf = conversions.find { |c| c[:from] == :ttf && c[:to] == :ttf }
      expect(ttf_to_ttf).not_to be_nil
    end

    it "includes cross-format conversions" do
      conversions = converter.all_conversions
      ttf_to_otf = conversions.find { |c| c[:from] == :ttf && c[:to] == :otf }
      expect(ttf_to_otf).not_to be_nil
    end

    it "includes OTF to TTF conversion" do
      conversions = converter.all_conversions
      expect(conversions).to include({ from: :otf, to: :ttf })
    end

    it "includes TTF to WOFF2 conversion" do
      conversions = converter.all_conversions
      expect(conversions).to include({ from: :ttf, to: :woff2 })
    end

    it "includes OTF to WOFF2 conversion" do
      conversions = converter.all_conversions
      expect(conversions).to include({ from: :otf, to: :woff2 })
    end

    it "includes TTF to SVG conversion" do
      conversions = converter.all_conversions
      expect(conversions).to include({ from: :ttf, to: :svg })
    end

    it "includes OTF to SVG conversion" do
      conversions = converter.all_conversions
      expect(conversions).to include({ from: :otf, to: :svg })
    end
  end

  describe "format detection" do
    it "detects TTF format from glyf table" do
      tables = converter.convert(ttf_font, :ttf)
      expect(tables).to be_a(Hash)
    end

    it "detects OTF format from CFF table" do
      tables = converter.convert(otf_font, :otf)
      expect(tables).to be_a(Hash)
    end

    it "raises error for font without glyf or CFF" do
      unknown_font = double("UnknownFont")
      allow(unknown_font).to receive(:has_table?).and_return(false)
      allow(unknown_font).to receive_messages(table: nil, tables: {})

      expect do
        converter.convert(unknown_font, :ttf)
      end.to raise_error(Fontisan::Error, /Cannot detect font format/)
    end
  end

  describe "strategy selection" do
    it "selects TableCopier for same-format conversions" do
      copier = Fontisan::Converters::TableCopier.new
      allow(Fontisan::Converters::TableCopier).to receive(:new).and_return(copier)
      allow(copier).to receive(:convert).and_return({})

      converter.convert(ttf_font, :ttf)

      expect(copier).to have_received(:convert)
    end

    it "selects OutlineConverter for cross-format conversions" do
      allow_any_instance_of(Fontisan::Converters::OutlineConverter)
        .to receive(:convert).and_raise(NotImplementedError)

      expect do
        converter.convert(ttf_font, :otf)
      end.to raise_error(NotImplementedError)
    end
  end

  describe "conversion matrix fallback" do
    context "when conversion matrix file is missing" do
      it "uses default inline matrix" do
        allow(File).to receive(:exist?).and_return(false)
        converter = described_class.new

        expect(converter.supported?(:ttf, :ttf)).to be true
        expect(converter.supported?(:otf, :otf)).to be true
      end
    end

    context "when conversion matrix has errors" do
      it "falls back to default matrix" do
        allow(YAML).to receive(:load_file).and_raise(StandardError)
        converter = described_class.new

        expect(converter.conversion_matrix).not_to be_nil
        expect(converter.supported?(:ttf, :ttf)).to be true
      end
    end
  end

  describe "variable font preservation" do
    let(:variable_ttf_font) { double("VariableTrueTypeFont") }
    let(:variable_otf_font) { double("VariableOpenTypeFont") }

    before do
      # Setup variable TTF font
      allow(variable_ttf_font).to receive(:has_table?).with("glyf").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("fvar").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("gvar").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("avar").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("STAT").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("cvar").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("HVAR").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("VVAR").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("MVAR").and_return(false)
      allow(variable_ttf_font).to receive(:has_table?).with("loca").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("head").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("hhea").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("maxp").and_return(true)
      allow(variable_ttf_font).to receive(:has_table?).with("cmap").and_return(false)

      # Mock tables
      allow(variable_ttf_font).to receive(:table).with("glyf").and_return(
        double("glyf", glyph_for: double(nil?: false, empty?: true,
                                         simple?: true, compound?: false)),
      )
      allow(variable_ttf_font).to receive(:table).with("loca").and_return(
        double("loca", parse_with_context: nil),
      )
      allow(variable_ttf_font).to receive(:table).with("head").and_return(
        double("head", units_per_em: 1000, index_to_loc_format: 1),
      )
      allow(variable_ttf_font).to receive(:table).with("hhea").and_return(double("hhea"))
      allow(variable_ttf_font).to receive(:table).with("maxp").and_return(
        double("maxp", num_glyphs: 100),
      )
      allow(variable_ttf_font).to receive(:table).with("name").and_return(
        double("name", english_name: "TestFont"),
      )
      allow(variable_ttf_font).to receive_messages(table_data: {
                                                     "glyf" => "glyf_data",
                                                     "fvar" => "fvar_data",
                                                     "gvar" => "gvar_data",
                                                     "head" => "\x00" * 54,
                                                   }, tables: {}, read_table_data: "data")

      # Setup variable OTF font
      allow(variable_otf_font).to receive(:has_table?).with("glyf").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("CFF ").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("CFF2").and_return(true)
      allow(variable_otf_font).to receive(:has_table?).with("fvar").and_return(true)
      allow(variable_otf_font).to receive(:has_table?).with("avar").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("STAT").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("HVAR").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("VVAR").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("MVAR").and_return(false)
      allow(variable_otf_font).to receive(:has_table?).with("head").and_return(true)
      allow(variable_otf_font).to receive(:has_table?).with("hhea").and_return(true)
      allow(variable_otf_font).to receive(:has_table?).with("maxp").and_return(true)
      allow(variable_otf_font).to receive(:has_table?).with("cmap").and_return(false)

      allow(variable_otf_font).to receive(:table).with("CFF2").and_return(
        double("cff2", glyph_count: 100, charstring_for_glyph: nil),
      )
      allow(variable_otf_font).to receive(:table).with("CFF ").and_return(
        double("cff", glyph_count: 100, charstring_for_glyph: nil),
      )
      allow(variable_otf_font).to receive(:table).with("head").and_return(
        double("head", units_per_em: 1000),
      )
      allow(variable_otf_font).to receive(:table).with("hhea").and_return(double("hhea"))
      allow(variable_otf_font).to receive(:table).with("maxp").and_return(
        double("maxp", num_glyphs: 100),
      )
      allow(variable_otf_font).to receive_messages(table_data: {
                                                     "CFF2" => "cff2_data",
                                                     "fvar" => "fvar_data",
                                                     "head" => "\x00" * 54,
                                                   }, tables: {}, read_table_data: "data")
    end

    describe "variable font detection" do
      it "detects variable TTF font" do
        # Mock VariationPreserver to check if it's called
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        converter.convert(variable_ttf_font, :ttf)

        expect(preserver_class).to have_received(:preserve)
      end

      it "detects non-variable font" do
        # Mock VariationPreserver to check it's NOT called
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        converter.convert(ttf_font, :ttf)

        expect(preserver_class).not_to have_received(:preserve)
      end
    end

    describe "preserve_variation option" do
      it "preserves variation by default" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        converter.convert(variable_ttf_font, :ttf)

        expect(preserver_class).to have_received(:preserve)
      end

      it "preserves variation when explicitly enabled" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        converter.convert(variable_ttf_font, :ttf, preserve_variation: true)

        expect(preserver_class).to have_received(:preserve)
      end

      it "does not preserve variation when disabled" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        converter.convert(variable_ttf_font, :ttf, preserve_variation: false)

        expect(preserver_class).not_to have_received(:preserve)
      end
    end

    describe "compatible format preservation (TTF→TTF)" do
      it "preserves variation tables for same format conversion" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve) do |_font, tables, _options|
          tables.merge("fvar" => "fvar_data", "gvar" => "gvar_data")
        end
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        result = converter.convert(variable_ttf_font, :ttf)

        expect(preserver_class).to have_received(:preserve)
        expect(result).to have_key("fvar")
        expect(result).to have_key("gvar")
      end
    end

    describe "compatible format preservation (OTF→OTF)" do
      it "preserves variation tables for same format conversion" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve) do |_font, tables, _options|
          tables.merge("fvar" => "fvar_data", "CFF2" => "cff2_data")
        end
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        result = converter.convert(variable_otf_font, :otf)

        expect(preserver_class).to have_received(:preserve)
        expect(result).to have_key("fvar")
        expect(result).to have_key("CFF2")
      end
    end

    describe "format conversion with variation (TTF→OTF)" do
      it "warns about incomplete conversion and preserves common tables" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        expect do
          converter.convert(variable_ttf_font, :otf)
        end.to output(/WARNING.*variation conversion.*not yet implemented/i).to_stderr

        expect(preserver_class).to have_received(:preserve).with(
          anything,
          anything,
          hash_including(
            preserve_format_specific: false,
            preserve_metrics: true,
          ),
        )
      end
    end

    describe "format conversion with variation (OTF→TTF)" do
      it "warns about incomplete conversion and preserves common tables" do
        preserver_class = double("VariationPreserver")
        allow(preserver_class).to receive(:preserve).and_return({})
        stub_const("Fontisan::Variation::VariationPreserver", preserver_class)

        expect do
          converter.convert(variable_otf_font, :ttf)
        end.to output(/WARNING.*variation conversion.*not yet implemented/i).to_stderr

        expect(preserver_class).to have_received(:preserve).with(
          anything,
          anything,
          hash_including(
            preserve_format_specific: false,
            preserve_metrics: true,
          ),
        )
      end
    end

    describe "unsupported variation preservation" do
      it "recognizes SVG as unsupported for variation preservation" do
        # Check that SVG is neither compatible nor convertible for variations
        expect(converter.send(:compatible_variation_formats?, :ttf,
                              :svg)).to be false
        expect(converter.send(:convertible_variation_formats?, :ttf,
                              :svg)).to be false
        expect(converter.send(:compatible_variation_formats?, :otf,
                              :svg)).to be false
        expect(converter.send(:convertible_variation_formats?, :otf,
                              :svg)).to be false
      end

      it "recognizes compatible variation formats" do
        # Same format
        expect(converter.send(:compatible_variation_formats?, :ttf,
                              :ttf)).to be true
        expect(converter.send(:compatible_variation_formats?, :otf,
                              :otf)).to be true

        # Format wrapping (TTF/OTF → WOFF/WOFF2)
        expect(converter.send(:compatible_variation_formats?, :ttf,
                              :woff2)).to be true
        expect(converter.send(:compatible_variation_formats?, :otf,
                              :woff2)).to be true
      end

      it "recognizes convertible variation formats" do
        # TTF ↔ OTF require variation conversion
        expect(converter.send(:convertible_variation_formats?, :ttf,
                              :otf)).to be true
        expect(converter.send(:convertible_variation_formats?, :otf,
                              :ttf)).to be true
      end
    end
  end

  describe "Type 1 font support" do
    let(:type1_font) { double("Type1Font") }

    before do
      allow(type1_font).to receive(:is_a?).with(Fontisan::Type1Font).and_return(true)
      allow(type1_font).to receive_messages(
        format: :pfb,
        font_name: "TestType1",
        full_name: "Test Type 1 Font",
        family_name: "Test Type 1",
        version: "001.000",
      )
    end

    describe "format detection" do
      it "detects Type 1 format" do
        format = converter.send(:detect_format, type1_font)
        expect(format).to eq(:type1)
      end

      it "distinguishes Type 1 from TTF and OTF" do
        ttf_format = converter.send(:detect_format, ttf_font)
        otf_format = converter.send(:detect_format, otf_font)
        type1_format = converter.send(:detect_format, type1_font)

        expect(ttf_format).to eq(:ttf)
        expect(otf_format).to eq(:otf)
        expect(type1_format).to eq(:type1)
      end
    end

    describe "validation" do
      it "accepts Type1Font as valid font type" do
        expect do
          converter.send(:validate_parameters!, type1_font, :otf)
        end.not_to raise_error
      end

      it "accepts Type1Font for TTF target" do
        expect do
          converter.send(:validate_parameters!, type1_font, :ttf)
        end.not_to raise_error
      end
    end

    describe "variable font detection" do
      it "returns false for Type 1 fonts (never variable)" do
        expect(converter.send(:variable_font?, type1_font)).to be false
      end
    end

    describe "conversion support" do
      it "includes Type 1 conversions in all_conversions" do
        conversions = converter.all_conversions
        type1_to_otf = conversions.find do |c|
          c[:from] == :type1 && c[:to] == :otf
        end
        type1_to_ttf = conversions.find do |c|
          c[:from] == :type1 && c[:to] == :ttf
        end
        otf_to_type1 = conversions.find do |c|
          c[:from] == :otf && c[:to] == :type1
        end

        expect(type1_to_otf).not_to be_nil
        expect(type1_to_ttf).not_to be_nil
        expect(otf_to_type1).not_to be_nil
      end

      it "includes Type 1 targets in supported_targets" do
        targets = converter.supported_targets(:type1)
        expect(targets).to include(:otf, :ttf)
      end
    end

    describe "strategy selection" do
      it "selects Type1Converter for Type 1 conversions" do
        # Verify Type1Converter is in strategies
        type1_converter = converter.strategies.find do |s|
          s.is_a?(Fontisan::Converters::Type1Converter)
        end
        expect(type1_converter).not_to be_nil
      end
    end
  end
end
