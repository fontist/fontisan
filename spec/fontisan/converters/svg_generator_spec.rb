# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/svg_generator"

RSpec.describe Fontisan::Converters::SvgGenerator do
  let(:font) { Fontisan::FontLoader.load(font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")) }
  let(:generator) { described_class.new }

  describe "#initialize" do
    it "creates generator" do
      expect(generator).to be_a(described_class)
    end
  end

  describe "#supported_conversions" do
    it "supports TTF to SVG" do
      conversions = generator.supported_conversions
      expect(conversions).to include(%i[ttf svg])
    end

    it "supports OTF to SVG" do
      conversions = generator.supported_conversions
      expect(conversions).to include(%i[otf svg])
    end
  end

  describe "#supports?" do
    it "returns true for TTF to SVG" do
      expect(generator.supports?(:ttf, :svg)).to be true
    end

    it "returns true for OTF to SVG" do
      expect(generator.supports?(:otf, :svg)).to be true
    end

    it "returns false for unsupported conversions" do
      expect(generator.supports?(:ttf, :woff2)).to be false
      expect(generator.supports?(:svg, :ttf)).to be false
    end
  end

  describe "#validate" do
    it "validates TTF to SVG conversion" do
      expect(generator.validate(font, :svg)).to be true
    end

    it "raises error for wrong target format" do
      expect do
        generator.validate(font, :woff2)
      end.to raise_error(Fontisan::Error, /only supports conversion to svg/)
    end

    it "raises error for missing required tables" do
      minimal_font = double("font")
      allow(minimal_font).to receive(:table).and_return(nil)

      expect do
        generator.validate(minimal_font, :svg)
      end.to raise_error(Fontisan::Error, /missing required table/)
    end
  end

  describe "#convert" do
    it "converts font to SVG" do
      result = generator.convert(font)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:svg_xml)
      expect(result[:svg_xml]).to be_a(String)
    end

    it "generates valid SVG XML structure" do
      result = generator.convert(font)
      svg = result[:svg_xml]

      expect(svg).to include('<?xml version="1.0"')
      expect(svg).to include("<svg")
      expect(svg).to include("<font")
      expect(svg).to include("<font-face")
      expect(svg).to include("</svg>")
    end

    it "includes glyphs in SVG" do
      result = generator.convert(font)
      svg = result[:svg_xml]

      expect(svg).to include("<glyph")
    end

    it "respects max_glyphs option" do
      result = generator.convert(font, max_glyphs: 5)
      svg = result[:svg_xml]

      # Should have limited number of glyphs
      glyph_count = svg.scan("<glyph").length
      expect(glyph_count).to be <= 5
    end

    it "handles glyph_ids option" do
      result = generator.convert(font, glyph_ids: [0, 65, 66])
      svg = result[:svg_xml]

      expect(svg).to be_a(String)
      expect(svg).to include("<svg")
    end
  end
end
