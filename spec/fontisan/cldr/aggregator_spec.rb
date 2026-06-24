# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/aggregator"
require "fontisan/cldr/index"
require "fontisan/models/cldr"

RSpec.describe Fontisan::Cldr::Aggregator do
  let(:index) do
    Fontisan::Cldr::Index.new(
      "en" => Set.new([97, 98, 99, 100]),       # a, b, c, d
      "fr" => Set.new([97, 98, 99, 100, 233]),  # + é
      "ja" => Set.new([0x3042, 0x3044]),        # あ, い
      "xx" => Set.new,                          # empty exemplar set
    )
  end

  describe ".aggregate" do
    it "returns one LanguageCoverage per language in the index" do
      result = described_class.aggregate([97, 98, 99], index)
      expect(result.length).to eq(4)
      expect(result).to all(be_a(Fontisan::Models::Cldr::LanguageCoverage))
    end

    it "computes coverage_ratio as covered / total, rounded to 4 dp" do
      result = described_class.aggregate([97, 98, 99], index)
      en = result.find { |lc| lc.language == "en" }
      expect(en.covered).to eq(3)
      expect(en.total).to eq(4)
      expect(en.coverage_ratio).to be_within(0.0001).of(0.75)
    end

    it "sets fully_supported true only when every codepoint is covered" do
      result = described_class.aggregate([97, 98, 99, 100], index)
      en = result.find { |lc| lc.language == "en" }
      expect(en.fully_supported).to be true
      expect(en.coverage_ratio).to eq(1.0)
    end

    it "sets fully_supported false for partial coverage" do
      result = described_class.aggregate([97, 98, 99], index)
      fr = result.find { |lc| lc.language == "fr" }
      expect(fr.fully_supported).to be false
    end

    it "reports ratio 0.0 and fully_supported false for empty exemplar sets" do
      result = described_class.aggregate([97, 98, 99], index)
      xx = result.find { |lc| lc.language == "xx" }
      expect(xx.total).to eq(0)
      expect(xx.coverage_ratio).to eq(0.0)
      expect(xx.fully_supported).to be false
    end

    it "reports ratio 0.0 when no codepoints overlap" do
      result = described_class.aggregate([0x3042], index)
      en = result.find { |lc| lc.language == "en" }
      expect(en.covered).to eq(0)
      expect(en.coverage_ratio).to eq(0.0)
      expect(en.fully_supported).to be false
    end

    it "sorts by descending coverage_ratio, then by language name" do
      result = described_class.aggregate([97, 98, 99, 100, 233], index)
      ratios = result.map(&:coverage_ratio)
      expect(ratios).to eq(ratios.sort.reverse)

      # Ties on ratio broken by language name ascending
      fully_supported = result.select(&:fully_supported).map(&:language)
      expect(fully_supported).to eq(fully_supported.sort)
    end

    it "treats font codepoints as a Set (deduplicates)" do
      result = described_class.aggregate([97, 97, 98, 98, 99], index)
      en = result.find { |lc| lc.language == "en" }
      expect(en.covered).to eq(3)
    end

    it "returns an empty array for an empty languages index" do
      empty_index = Fontisan::Cldr::Index.new({})
      expect(described_class.aggregate([97], empty_index)).to eq([])
    end
  end
end
