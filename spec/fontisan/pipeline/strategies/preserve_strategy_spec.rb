# frozen_string_literal: true

require "spec_helper"
require "fontisan/pipeline/strategies/preserve_strategy"

RSpec.describe Fontisan::Pipeline::Strategies::PreserveStrategy do
  let(:variable_ttf_path) { font_fixture_path("MonaSans", "fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf") }
  let(:variable_font) { Fontisan::FontLoader.load(variable_ttf_path, mode: :full) }

  describe "#initialize" do
    it "initializes with default options" do
      strategy = described_class.new
      expect(strategy).to be_a(described_class)
    end

    it "initializes with custom options" do
      strategy = described_class.new(preserve_metrics: false)
      expect(strategy).to be_a(described_class)
    end
  end

  describe "#resolve" do
    it "returns all font tables" do
      strategy = described_class.new
      tables = strategy.resolve(variable_font)

      expect(tables).to be_a(Hash)
      expect(tables.keys).not_to be_empty
    end

    it "preserves variation tables" do
      strategy = described_class.new
      tables = strategy.resolve(variable_font)

      # Should have variation tables
      expect(tables).to have_key("fvar")
      expect(tables).to have_key("gvar")
    end

    it "preserves base tables" do
      strategy = described_class.new
      tables = strategy.resolve(variable_font)

      expect(tables).to have_key("head")
      expect(tables).to have_key("name")
      expect(tables).to have_key("glyf")
      expect(tables).to have_key("loca")
    end

    it "preserves metrics variation tables" do
      strategy = described_class.new
      tables = strategy.resolve(variable_font)

      # Skip if font doesn't have these tables
      if variable_font.has_table?("HVAR")
        expect(tables).to have_key("HVAR")
      end
    end

    it "preserves all tables when preserve_all is true" do
      strategy = described_class.new(preserve_all: true)
      tables = strategy.resolve(variable_font)

      original_count = variable_font.table_data.keys.length
      expect(tables.keys.length).to eq(original_count)
    end
  end

  describe "#preserves_variation?" do
    it "returns true" do
      strategy = described_class.new
      expect(strategy.preserves_variation?).to be true
    end
  end

  describe "#strategy_name" do
    it "returns :preserve" do
      strategy = described_class.new
      expect(strategy.strategy_name).to eq(:preserve)
    end
  end
end
