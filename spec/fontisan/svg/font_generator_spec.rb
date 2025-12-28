# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg/font_generator"

RSpec.describe Fontisan::Svg::FontGenerator do
  let(:font) { Fontisan::FontLoader.load(font_fixture_path("MonaSans", "fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")) }
  let(:glyph_data) do
    {
      0 => {
        outline: nil,
        unicode: nil,
        name: ".notdef",
        advance: 500,
      },
      65 => {
        outline: create_test_outline(65),
        unicode: "A",
        name: "A",
        advance: 600,
      },
    }
  end
  let(:generator) { described_class.new(font, glyph_data) }

  def create_test_outline(glyph_id)
    Fontisan::Models::GlyphOutline.new(
      glyph_id: glyph_id,
      contours: [
        [
          { x: 100, y: 0, on_curve: true },
          { x: 200, y: 700, on_curve: true },
          { x: 300, y: 0, on_curve: true },
        ],
      ],
      bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
    )
  end

  describe "#initialize" do
    it "creates generator with valid parameters" do
      expect(generator.font).to eq(font)
      expect(generator.glyph_data).to eq(glyph_data)
    end

    it "raises error for nil font" do
      expect do
        described_class.new(nil, glyph_data)
      end.to raise_error(ArgumentError, /Font cannot be nil/)
    end

    it "raises error for invalid glyph_data" do
      expect do
        described_class.new(font, "not a hash")
      end.to raise_error(ArgumentError, /glyph_data must be a Hash/)
    end

    it "accepts options" do
      gen = described_class.new(font, glyph_data, pretty_print: false)
      expect(gen.options[:pretty_print]).to be(false)
    end
  end

  describe "#generate" do
    it "generates complete SVG font XML" do
      svg = generator.generate

      expect(svg).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(svg).to include('<svg xmlns="http://www.w3.org/2000/svg">')
      expect(svg).to include("<defs>")
      expect(svg).to include("<font")
      expect(svg).to include("<font-face")
      expect(svg).to include("<missing-glyph")
      expect(svg).to include("<glyph")
      expect(svg).to include("</font>")
      expect(svg).to include("</defs>")
      expect(svg).to include("</svg>")
    end

    it "includes font ID" do
      svg = generator.generate
      expect(svg).to match(/<font id="[^"]+"/)
    end

    it "includes default advance width" do
      svg = generator.generate
      expect(svg).to match(/horiz-adv-x="\d+"/)
    end

    it "generates glyphs from glyph_data" do
      svg = generator.generate
      expect(svg).to include('unicode="A"')
    end

    it "uses custom font ID from options" do
      gen = described_class.new(font, glyph_data, font_id: "CustomFont")
      svg = gen.generate
      expect(svg).to include('id="CustomFont"')
    end
  end
end
