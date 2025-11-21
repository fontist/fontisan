# frozen_string_literal: true

require "spec_helper"
require "fontisan/svg/glyph_generator"
require "fontisan/svg/view_box_calculator"
require "fontisan/models/glyph_outline"

RSpec.describe Fontisan::Svg::GlyphGenerator do
  let(:calculator) do
    Fontisan::Svg::ViewBoxCalculator.new(
      units_per_em: 1000,
      ascent: 800,
      descent: -200,
    )
  end
  let(:generator) { described_class.new(calculator) }

  describe "#initialize" do
    it "creates generator with valid calculator" do
      expect(generator.calculator).to eq(calculator)
    end

    it "raises error for nil calculator" do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /Calculator cannot be nil/)
    end
  end

  describe "#generate_glyph_xml" do
    let(:outline) do
      Fontisan::Models::GlyphOutline.new(
        glyph_id: 65,
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

    it "generates glyph XML element" do
      xml = generator.generate_glyph_xml(
        outline,
        unicode: "A",
        advance_width: 600,
      )

      expect(xml).to include("<glyph")
      expect(xml).to include('unicode="A"')
      expect(xml).to include('horiz-adv-x="600"')
      expect(xml).to include("d=")
      expect(xml).to end_with("/>")
    end

    it "includes glyph name when provided" do
      xml = generator.generate_glyph_xml(
        outline,
        unicode: "A",
        glyph_name: "A",
        advance_width: 600,
      )

      expect(xml).to include('glyph-name="A"')
    end

    it "generates SVG path with Y-axis transformation" do
      xml = generator.generate_glyph_xml(outline, advance_width: 600)

      # Path should be transformed with Y-axis flip
      expect(xml).to match(/d="M \d+ \d+.*Z"/)
    end

    it "handles empty outline" do
      empty_outline = Fontisan::Models::GlyphOutline.new(
        glyph_id: 32,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      xml = generator.generate_glyph_xml(empty_outline, advance_width: 250)
      expect(xml).to include('horiz-adv-x="250"')
      expect(xml).not_to include("d=")
    end

    it "escapes XML characters in unicode" do
      xml = generator.generate_glyph_xml(
        outline,
        unicode: "<",
        advance_width: 600,
      )

      expect(xml).to include('unicode="&lt;"')
    end

    it "uses custom indentation" do
      xml = generator.generate_glyph_xml(
        outline,
        advance_width: 600,
        indent: "  ",
      )

      expect(xml).to start_with("  <glyph")
    end
  end

  describe "#generate_missing_glyph" do
    it "generates missing-glyph element" do
      xml = generator.generate_missing_glyph(advance_width: 500)

      expect(xml).to include("<missing-glyph")
      expect(xml).to include('horiz-adv-x="500"')
      expect(xml).to end_with("/>")
    end

    it "uses default advance width" do
      xml = generator.generate_missing_glyph

      expect(xml).to include('horiz-adv-x="500"')
    end

    it "uses custom indentation" do
      xml = generator.generate_missing_glyph(indent: "  ")
      expect(xml).to start_with("  <missing-glyph")
    end
  end

  describe "#generate_svg_path" do
    it "generates SVG path from simple contour" do
      outline = Fontisan::Models::GlyphOutline.new(
        glyph_id: 1,
        contours: [
          [
            { x: 0, y: 0, on_curve: true },
            { x: 100, y: 0, on_curve: true },
            { x: 100, y: 100, on_curve: true },
            { x: 0, y: 100, on_curve: true },
          ],
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
      )

      path = generator.generate_svg_path(outline)

      expect(path).to include("M")
      expect(path).to include("L")
      expect(path).to include("Z")
    end

    it "handles quadratic curves" do
      outline = Fontisan::Models::GlyphOutline.new(
        glyph_id: 2,
        contours: [
          [
            { x: 0, y: 0, on_curve: true },
            { x: 50, y: 100, on_curve: false },
            { x: 100, y: 0, on_curve: true },
          ],
        ],
        bbox: { x_min: 0, y_min: 0, x_max: 100, y_max: 100 },
      )

      path = generator.generate_svg_path(outline)

      expect(path).to include("M")
      expect(path).to include("Q")
      expect(path).to include("Z")
    end

    it "returns empty string for empty outline" do
      outline = Fontisan::Models::GlyphOutline.new(
        glyph_id: 3,
        contours: [],
        bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
      )

      path = generator.generate_svg_path(outline)
      expect(path).to eq("")
    end
  end
end
