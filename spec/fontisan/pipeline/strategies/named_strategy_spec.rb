# frozen_string_literal: true

require "spec_helper"
require "fontisan/pipeline/strategies/named_strategy"

RSpec.describe Fontisan::Pipeline::Strategies::NamedStrategy do
  let(:variable_ttf_path) do
    font_fixture_path("MonaSans",
                      "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf")
  end
  let(:variable_font) { Fontisan::FontLoader.load(variable_ttf_path, mode: :full) }

  describe "#initialize" do
    it "initializes with instance_index" do
      strategy = described_class.new(instance_index: 0)
      expect(strategy).to be_a(described_class)
    end

    it "raises error without instance_index" do
      expect do
        described_class.new
      end.to raise_error(ArgumentError, /instance_index is required/i)
    end

    it "raises error with nil instance_index" do
      expect do
        described_class.new(instance_index: nil)
      end.to raise_error(ArgumentError, /instance_index is required/i)
    end
  end

  describe "#resolve" do
    it "generates instance from named instance" do
      strategy = described_class.new(instance_index: 0)
      tables = strategy.resolve(variable_font)

      expect(tables).to be_a(Hash)
      expect(tables.keys).not_to be_empty
    end

    it "removes variation tables" do
      strategy = described_class.new(instance_index: 0)
      tables = strategy.resolve(variable_font)

      # Should not have variation tables
      expect(tables).not_to have_key("fvar")
      expect(tables).not_to have_key("gvar")
    end

    it "preserves base tables" do
      strategy = described_class.new(instance_index: 0)
      tables = strategy.resolve(variable_font)

      expect(tables).to have_key("head")
      expect(tables).to have_key("name")
      expect(tables).to have_key("glyf")
    end

    it "raises error for invalid instance index" do
      strategy = described_class.new(instance_index: 999)

      expect do
        strategy.resolve(variable_font)
      end.to raise_error(ArgumentError, /invalid instance index/i)
    end

    it "raises error for negative instance index" do
      strategy = described_class.new(instance_index: -1)

      expect do
        strategy.resolve(variable_font)
      end.to raise_error(ArgumentError, /invalid instance index/i)
    end

    it "extracts coordinates from fvar instance" do
      fvar = variable_font.table("fvar")
      next if fvar.instances.empty?

      strategy = described_class.new(instance_index: 0)
      tables = strategy.resolve(variable_font)

      # Should successfully generate instance
      expect(tables).to be_a(Hash)
    end
  end

  describe "#preserves_variation?" do
    it "returns false" do
      strategy = described_class.new(instance_index: 0)
      expect(strategy.preserves_variation?).to be false
    end
  end

  describe "#strategy_name" do
    it "returns :named" do
      strategy = described_class.new(instance_index: 0)
      expect(strategy.strategy_name).to eq(:named)
    end
  end
end
