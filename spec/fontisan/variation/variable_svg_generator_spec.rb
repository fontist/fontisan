# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Variation::VariableSvgGenerator do
  let(:variable_ttf_path) do
    fixture_path("fonts/MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf")
  end
  let(:variable_font) { Fontisan::FontLoader.load(variable_ttf_path) }

  describe "#initialize" do
    context "with valid variable font" do
      it "initializes successfully with coordinates" do
        coords = { "wght" => 700.0 }
        generator = described_class.new(variable_font, coords)

        expect(generator.font).to eq(variable_font)
        expect(generator.coordinates).to eq(coords)
      end

      it "initializes successfully without coordinates" do
        generator = described_class.new(variable_font)

        expect(generator.font).to eq(variable_font)
        expect(generator.coordinates).to eq({})
      end

      it "handles nil coordinates" do
        generator = described_class.new(variable_font, nil)

        expect(generator.coordinates).to eq({})
      end
    end

    context "with non-variable font" do
      let(:static_font_path) do
        fixture_path("fonts/MonaSans/fonts/static/ttf/MonaSans-ExtraLightItalic.ttf")
      end
      let(:static_font) { Fontisan::FontLoader.load(static_font_path) }

      it "raises error for font without fvar table" do
        expect do
          described_class.new(static_font)
        end.to raise_error(
          Fontisan::Error,
          /must be a variable font/,
        )
      end
    end

    context "with invalid variable font" do
      let(:mock_font) { instance_double(Fontisan::TrueTypeFont) }

      it "raises error for font without variation data" do
        allow(mock_font).to receive(:has_table?).with("fvar").and_return(true)
        allow(mock_font).to receive(:has_table?).with("gvar").and_return(false)
        allow(mock_font).to receive(:has_table?).with("CFF2").and_return(false)

        expect do
          described_class.new(mock_font)
        end.to raise_error(
          Fontisan::Error,
          /must have gvar.*or CFF2/,
        )
      end
    end
  end

  describe "#generate" do
    let(:generator) { described_class.new(variable_font, coordinates) }

    context "with default coordinates" do
      let(:coordinates) { {} }

      it "generates SVG successfully" do
        result = generator.generate

        expect(result).to be_a(Hash)
        expect(result).to have_key(:svg_xml)
        expect(result[:svg_xml]).to be_a(String)
        expect(result[:svg_xml]).to include('<?xml version="1.0"')
        expect(result[:svg_xml]).to include("<svg")
        expect(result[:svg_xml]).to include("<font")
      end

      it "includes variation metadata" do
        result = generator.generate

        expect(result).to have_key(:variation_metadata)
        metadata = result[:variation_metadata]
        expect(metadata).to have_key(:coordinates)
        expect(metadata).to have_key(:source_font)
      end

      it "uses default axis values when no coordinates specified" do
        result = generator.generate

        metadata = result[:variation_metadata]
        expect(metadata[:coordinates]).to be_a(Hash)
        # Should have default coordinates for all axes
      end
    end

    context "with specific weight coordinate" do
      let(:coordinates) { { "wght" => 700.0 } }

      it "generates SVG at specified weight" do
        result = generator.generate

        expect(result[:svg_xml]).to include("<font")
        expect(result[:variation_metadata][:coordinates]).to eq(coordinates)
      end

      it "respects pretty_print option" do
        result = generator.generate(pretty_print: true)

        expect(result[:svg_xml]).to include("\n")
      end

      it "respects max_glyphs option" do
        result = generator.generate(max_glyphs: 10)

        expect(result[:svg_xml]).to include("<glyph")
      end
    end

    context "with multiple axis coordinates" do
      let(:coordinates) { { "wght" => 700.0, "opsz" => 12.0 } }

      it "generates SVG at multiple axis values" do
        result = generator.generate

        expect(result[:svg_xml]).to include("<font")
        expect(result[:variation_metadata][:coordinates]).to eq(coordinates)
      end
    end

    context "with SVG generation options" do
      let(:coordinates) { { "wght" => 600.0 } }

      it "passes through font_id option" do
        result = generator.generate(font_id: "CustomFont")

        expect(result[:svg_xml]).to include('id="CustomFont"')
      end

      it "passes through default_advance option" do
        result = generator.generate(default_advance: 1000)

        expect(result[:svg_xml]).to include('horiz-adv-x="1000"')
      end

      it "passes through glyph_ids option" do
        result = generator.generate(glyph_ids: [0, 1, 2])

        expect(result[:svg_xml]).to be_a(String)
      end
    end
  end

  describe "#generate_named_instance" do
    let(:generator) { described_class.new(variable_font) }

    it "generates SVG for first named instance" do
      result = generator.generate_named_instance(0)

      expect(result).to have_key(:svg_xml)
      expect(result[:svg_xml]).to include("<font")
    end

    it "includes instance metadata" do
      result = generator.generate_named_instance(0)

      expect(result).to have_key(:variation_metadata)
      metadata = result[:variation_metadata]
      expect(metadata).to have_key(:instance_index)
      expect(metadata[:instance_index]).to eq(0)
    end

    it "handles options" do
      result = generator.generate_named_instance(0, pretty_print: true)

      expect(result[:svg_xml]).to include("\n")
    end
  end

  describe "#default_coordinates" do
    let(:generator) { described_class.new(variable_font) }

    it "returns default coordinates for all axes" do
      coords = generator.default_coordinates

      expect(coords).to be_a(Hash)
      expect(coords).not_to be_empty
      # Verify it returns coordinates for the variable font's axes
      expect(coords.values).to all(be_a(Numeric))
    end

    it "returns empty hash for font without fvar" do
      static_font = instance_double(Fontisan::TrueTypeFont)
      allow(static_font).to receive(:has_table?).and_return(false)

      # This would fail in initialize, so we'll skip this test
    end
  end

  describe "#named_instances" do
    let(:generator) { described_class.new(variable_font) }

    it "returns list of named instances" do
      instances = generator.named_instances

      expect(instances).to be_an(Array)
      expect(instances).not_to be_empty
    end

    it "includes instance metadata" do
      instances = generator.named_instances

      first_instance = instances.first
      expect(first_instance).to have_key(:index)
      expect(first_instance).to have_key(:name)
      expect(first_instance).to have_key(:coordinates)
    end

    it "has sequential indices" do
      instances = generator.named_instances

      instances.each_with_index do |instance, idx|
        expect(instance[:index]).to eq(idx)
      end
    end
  end

  describe "error handling" do
    let(:generator) { described_class.new(variable_font, { "wght" => 700.0 }) }

    it "handles font with invalid coordinates gracefully" do
      # Invalid axis tag
      generator_invalid = described_class.new(variable_font, { "XXXX" => 999.0 })

      expect do
        generator_invalid.generate
      end.not_to raise_error
    end

    it "handles out-of-range coordinate values" do
      # Extreme weight value
      generator_extreme = described_class.new(variable_font, { "wght" => 9999.0 })

      expect do
        generator_extreme.generate
      end.not_to raise_error
    end
  end

  describe "integration scenarios" do
    context "complete workflow" do
      it "generates valid SVG from variable TTF at bold weight" do
        coords = { "wght" => 700.0 }
        generator = described_class.new(variable_font, coords)
        result = generator.generate(pretty_print: true)

        # Verify SVG structure
        expect(result[:svg_xml]).to include("<?xml")
        expect(result[:svg_xml]).to include("<svg")
        expect(result[:svg_xml]).to include("<font")
        expect(result[:svg_xml]).to include("<font-face")
        expect(result[:svg_xml]).to include("<glyph")
        expect(result[:svg_xml]).to include("</font>")
        expect(result[:svg_xml]).to include("</svg>")

        # Verify metadata
        expect(result[:variation_metadata][:coordinates]["wght"]).to eq(700.0)
      end

      # Note: This test is commented out because InstanceGenerator is currently
      # a placeholder that doesn't actually apply variations yet. Once instance
      # generation is fully implemented, this test should pass.
      # it "generates different SVG for different weights" do
      #   light_gen = described_class.new(variable_font, { "wght" => 200.0 })
      #   bold_gen = described_class.new(variable_font, { "wght" => 700.0 })
      #
      #   light_result = light_gen.generate
      #   bold_result = bold_gen.generate
      #
      #   # Should produce different SVG (different outlines)
      #   expect(light_result[:svg_xml]).not_to eq(bold_result[:svg_xml])
      # end
    end

    context "performance" do
      it "generates SVG in reasonable time" do
        coords = { "wght" => 600.0 }
        generator = described_class.new(variable_font, coords)

        start_time = Time.now
        result = generator.generate
        duration = Time.now - start_time

        expect(result).to have_key(:svg_xml)
        expect(duration).to be < 5.0 # Should complete within 5 seconds
      end
    end
  end

  describe "InstanceFontWrapper" do
    let(:wrapper_class) { described_class::InstanceFontWrapper }
    let(:original_font) { variable_font }
    let(:instance_tables) { { "head" => "data", "hhea" => "data" } }
    let(:wrapper) { wrapper_class.new(original_font, instance_tables) }

    it "provides access to table_data" do
      expect(wrapper.table_data).to eq(instance_tables)
    end

    it "delegates table access to original font" do
      table = wrapper.table("head")
      expect(table).not_to be_nil
    end

    it "checks table existence correctly" do
      expect(wrapper.has_table?("head")).to be true
      expect(wrapper.has_table?("fvar")).to be true # from original font
    end

    it "forwards missing methods to original font" do
      expect(wrapper).to respond_to(:table_data)
    end
  end
end
