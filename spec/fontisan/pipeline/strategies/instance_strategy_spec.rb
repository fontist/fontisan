# frozen_string_literal: true

require "spec_helper"
require "fontisan/pipeline/strategies/instance_strategy"

RSpec.describe Fontisan::Pipeline::Strategies::InstanceStrategy do
  let(:variable_ttf_path) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:variable_font) { Fontisan::FontLoader.load(variable_ttf_path, mode: :full) }

  describe "#initialize" do
    it "initializes with coordinates" do
      strategy = described_class.new(coordinates: { "wght" => 700.0 })
      expect(strategy).to be_a(described_class)
    end

    it "initializes with empty coordinates" do
      strategy = described_class.new(coordinates: {})
      expect(strategy).to be_a(described_class)
    end

    it "initializes without coordinates option" do
      strategy = described_class.new
      expect(strategy).to be_a(described_class)
    end
  end

  describe "#resolve" do
    it "generates static instance at coordinates" do
      strategy = described_class.new(coordinates: { "wght" => 700.0 })
      tables = strategy.resolve(variable_font)

      expect(tables).to be_a(Hash)
      expect(tables.keys).not_to be_empty
    end

    it "removes variation tables" do
      strategy = described_class.new(coordinates: { "wght" => 700.0 })
      tables = strategy.resolve(variable_font)

      # Should not have variation tables
      expect(tables).not_to have_key("fvar")
      expect(tables).not_to have_key("gvar")
      expect(tables).not_to have_key("avar")
    end

    it "preserves base tables" do
      strategy = described_class.new(coordinates: { "wght" => 700.0 })
      tables = strategy.resolve(variable_font)

      expect(tables).to have_key("head")
      expect(tables).to have_key("name")
      expect(tables).to have_key("glyf")
    end

    it "uses default coordinates when none provided" do
      strategy = described_class.new
      tables = strategy.resolve(variable_font)

      expect(tables).to be_a(Hash)
      expect(tables).not_to have_key("fvar")
    end

    it "validates coordinates" do
      strategy = described_class.new(coordinates: { "wght" => 9999.0 })

      expect do
        strategy.resolve(variable_font)
      end.to raise_error(Fontisan::InvalidCoordinatesError)
    end

    it "handles multiple axes" do
      # If font has multiple axes
      fvar = variable_font.table("fvar")
      if fvar.axes.length > 1
        coords = fvar.axes.each_with_object({}) do |axis, hash|
          hash[axis.axis_tag] = axis.default_value
        end

        strategy = described_class.new(coordinates: coords)
        tables = strategy.resolve(variable_font)

        expect(tables).to be_a(Hash)
      end
    end
  end

  describe "#preserves_variation?" do
    it "returns false" do
      strategy = described_class.new(coordinates: { "wght" => 700.0 })
      expect(strategy.preserves_variation?).to be false
    end
  end

  describe "#strategy_name" do
    it "returns :instance" do
      strategy = described_class.new
      expect(strategy.strategy_name).to eq(:instance)
    end
  end
end
