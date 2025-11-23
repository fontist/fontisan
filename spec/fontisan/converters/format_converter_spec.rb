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
    allow(ttf_font).to receive(:table).with("glyf").and_return(double)
    allow(ttf_font).to receive(:table).with("CFF ").and_return(nil)
    allow(ttf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(ttf_font).to receive_messages(tables: { "glyf" => double,
                                                  "head" => double },
                                        table_data: { "glyf" => "glyf_data",
                                                      "head" => "head_data" },
                                        read_table_data: "data")

    # Add stubs for OutlineConverter validation
    allow(ttf_font).to receive(:has_table?).with("loca").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("head").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("hhea").and_return(true)
    allow(ttf_font).to receive(:has_table?).with("maxp").and_return(true)
    allow(ttf_font).to receive(:table).with("loca").and_return(double("loca"))
    allow(ttf_font).to receive(:table).with("head").and_return(double("head",
                                                                      units_per_em: 1000))
    allow(ttf_font).to receive(:table).with("hhea").and_return(double("hhea"))
    allow(ttf_font).to receive(:table).with("maxp").and_return(double("maxp",
                                                                      num_glyphs: 100))

    allow(otf_font).to receive(:has_table?).with("glyf").and_return(false)
    allow(otf_font).to receive(:has_table?).with("CFF ").and_return(true)
    allow(otf_font).to receive(:has_table?).with("CFF2").and_return(false)
    allow(otf_font).to receive(:table).with("CFF ").and_return(double)
    allow(otf_font).to receive(:table).with("CFF2").and_return(nil)
    allow(otf_font).to receive(:table).with("glyf").and_return(nil)
    allow(otf_font).to receive_messages(tables: { "CFF " => double,
                                                  "head" => double },
                                        table_data: { "CFF " => "CFF _data",
                                                      "head" => "head_data" },
                                        read_table_data: "data")

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
      xit "raises compound glyph error for TTF to OTF (real font)" do
        # OutlineConverter is implemented but doesn't support compound glyphs
        # This will attempt conversion but fail on compound glyphs
        expect do
          converter.convert(ttf_font, :otf)
        end.to raise_error(Fontisan::Error)
      end

      xit "raises compound glyph error for OTF to TTF (real font)" do
        # OutlineConverter is implemented but doesn't support compound glyphs
        expect do
          converter.convert(otf_font, :ttf)
        end.to raise_error(Fontisan::Error)
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
end
