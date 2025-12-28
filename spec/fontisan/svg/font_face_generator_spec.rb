# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg/font_face_generator"

RSpec.describe Fontisan::Svg::FontFaceGenerator do
  let(:font) { Fontisan::FontLoader.load(font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")) }
  let(:generator) { described_class.new(font) }

  describe "#initialize" do
    it "creates generator with valid font" do
      expect(generator.font).to eq(font)
    end

    it "raises error for nil font" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /Font cannot be nil/)
    end

    it "raises error for invalid font" do
      expect do
        described_class.new("not a font")
      end.to raise_error(ArgumentError, /Font must respond to :table method/)
    end
  end

  describe "#generate_attributes" do
    it "generates font-face attributes hash" do
      attributes = generator.generate_attributes

      expect(attributes).to be_a(Hash)
      expect(attributes).to have_key(:font_family)
      expect(attributes).to have_key(:units_per_em)
      expect(attributes).to have_key(:ascent)
      expect(attributes).to have_key(:descent)
    end

    it "extracts font family name" do
      attributes = generator.generate_attributes
      expect(attributes[:font_family]).to be_a(String)
      expect(attributes[:font_family]).not_to be_empty
    end

    it "extracts units per em" do
      attributes = generator.generate_attributes
      expect(attributes[:units_per_em]).to be_a(Integer)
      expect(attributes[:units_per_em]).to be > 0
    end

    it "extracts ascent" do
      attributes = generator.generate_attributes
      expect(attributes[:ascent]).to be_a(Integer)
    end

    it "extracts descent" do
      attributes = generator.generate_attributes
      expect(attributes[:descent]).to be_a(Integer)
    end

    it "includes optional attributes when available" do
      attributes = generator.generate_attributes
      # These may or may not be present depending on font
      expect(attributes).to have_key(:font_weight)
      expect(attributes).to have_key(:font_style)
    end
  end

  describe "#generate_xml" do
    it "generates font-face XML element" do
      xml = generator.generate_xml

      expect(xml).to include("<font-face")
      expect(xml).to include("font-family=")
      expect(xml).to include("units-per-em=")
      expect(xml).to include("ascent=")
      expect(xml).to include("descent=")
      expect(xml).to end_with("/>")
    end

    it "uses custom indentation" do
      xml = generator.generate_xml(indent: "  ")
      expect(xml).to start_with("  <font-face")
    end

    it "includes all required attributes" do
      xml = generator.generate_xml

      expect(xml).to match(/font-family="[^"]+"/)
      expect(xml).to match(/units-per-em="\d+"/)
      expect(xml).to match(/ascent="-?\d+"/)
      expect(xml).to match(/descent="-?\d+"/)
    end
  end

  describe "attribute extraction with missing tables" do
    let(:minimal_font) do
      double("font").tap do |f|
        allow(f).to receive(:respond_to?).with(:table).and_return(true)
        allow(f).to receive(:table).and_return(nil)
      end
    end

    it "provides default values when tables are missing" do
      generator = described_class.new(minimal_font)
      attributes = generator.generate_attributes

      expect(attributes[:font_family]).to eq("Unknown")
      expect(attributes[:units_per_em]).to eq(1000)
      expect(attributes[:ascent]).to eq(800)
      expect(attributes[:descent]).to eq(-200)
    end
  end
end
