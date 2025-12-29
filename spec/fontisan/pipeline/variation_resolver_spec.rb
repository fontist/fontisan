# frozen_string_literal: true

require "spec_helper"
require "fontisan/pipeline/variation_resolver"

RSpec.describe Fontisan::Pipeline::VariationResolver do
  let(:variable_ttf_path) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:variable_font) { Fontisan::FontLoader.load(variable_ttf_path, mode: :full) }

  describe "#initialize" do
    it "initializes with font and preserve strategy" do
      resolver = described_class.new(variable_font, strategy: :preserve)
      expect(resolver).to be_a(described_class)
    end

    it "initializes with font and instance strategy" do
      resolver = described_class.new(
        variable_font,
        strategy: :instance,
        coordinates: { "wght" => 700.0 },
      )
      expect(resolver).to be_a(described_class)
    end

    it "initializes with font and named strategy" do
      resolver = described_class.new(
        variable_font,
        strategy: :named,
        instance_index: 0,
      )
      expect(resolver).to be_a(described_class)
    end

    it "raises error for unknown strategy" do
      expect do
        described_class.new(variable_font, strategy: :unknown)
      end.to raise_error(ArgumentError, /Unknown strategy/)
    end

    it "raises error for missing strategy" do
      expect do
        described_class.new(variable_font)
      end.to raise_error(ArgumentError, /strategy is required/)
    end
  end

  describe "#resolve" do
    context "with preserve strategy" do
      it "preserves variation tables" do
        resolver = described_class.new(variable_font, strategy: :preserve)
        tables = resolver.resolve

        # Should have variation tables
        expect(tables).to have_key("fvar")
        expect(tables).to have_key("gvar")
      end

      it "preserves all font tables" do
        resolver = described_class.new(variable_font, strategy: :preserve)
        tables = resolver.resolve

        # Should have base tables
        expect(tables).to have_key("head")
        expect(tables).to have_key("name")
      end
    end

    context "with instance strategy" do
      it "generates static instance at coordinates" do
        coordinates = { "wght" => 700.0 }
        resolver = described_class.new(
          variable_font,
          strategy: :instance,
          coordinates: coordinates,
        )
        tables = resolver.resolve

        # Should remove variation tables
        expect(tables).not_to have_key("fvar")
        expect(tables).not_to have_key("gvar")

        # Should have base tables
        expect(tables).to have_key("head")
        expect(tables).to have_key("glyf")
      end

      it "uses default coordinates when none provided" do
        resolver = described_class.new(variable_font, strategy: :instance)
        tables = resolver.resolve

        expect(tables).to be_a(Hash)
        expect(tables).not_to have_key("fvar")
      end

      it "validates coordinates" do
        expect do
          described_class.new(
            variable_font,
            strategy: :instance,
            coordinates: { "wght" => 9999.0 },
          )
        end.to raise_error(Fontisan::InvalidCoordinatesError)
      end
    end

    context "with named strategy" do
      it "generates instance from named instance" do
        resolver = described_class.new(
          variable_font,
          strategy: :named,
          instance_index: 0,
        )
        tables = resolver.resolve

        # Should remove variation tables
        expect(tables).not_to have_key("fvar")
        expect(tables).not_to have_key("gvar")
      end

      it "raises error for invalid instance index" do
        expect do
          described_class.new(
            variable_font,
            strategy: :named,
            instance_index: 999,
          )
        end.to raise_error(ArgumentError, /invalid instance index/i)
      end

      it "requires instance_index option" do
        expect do
          described_class.new(variable_font, strategy: :named)
        end.to raise_error(ArgumentError, /instance_index is required/i)
      end
    end
  end

  describe "#preserves_variation?" do
    it "returns true for preserve strategy" do
      resolver = described_class.new(variable_font, strategy: :preserve)
      expect(resolver.preserves_variation?).to be true
    end

    it "returns false for instance strategy" do
      resolver = described_class.new(
        variable_font,
        strategy: :instance,
        coordinates: { "wght" => 700.0 },
      )
      expect(resolver.preserves_variation?).to be false
    end

    it "returns false for named strategy" do
      resolver = described_class.new(
        variable_font,
        strategy: :named,
        instance_index: 0,
      )
      expect(resolver.preserves_variation?).to be false
    end
  end

  describe "#strategy_name" do
    it "returns :preserve for preserve strategy" do
      resolver = described_class.new(variable_font, strategy: :preserve)
      expect(resolver.strategy_name).to eq(:preserve)
    end

    it "returns :instance for instance strategy" do
      resolver = described_class.new(variable_font, strategy: :instance)
      expect(resolver.strategy_name).to eq(:instance)
    end

    it "returns :named for named strategy" do
      resolver = described_class.new(
        variable_font,
        strategy: :named,
        instance_index: 0,
      )
      expect(resolver.strategy_name).to eq(:named)
    end
  end
end
