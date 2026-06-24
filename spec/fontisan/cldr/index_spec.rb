# frozen_string_literal: true

require "spec_helper"
require "fontisan/cldr/index"
require "json"

RSpec.describe Fontisan::Cldr::Index do
  let(:entries) do
    {
      "en" => Set.new([97, 98, 99]),         # a, b, c
      "fr" => Set.new([97, 98, 99, 233]),    # a, b, c, é
      "ja" => Set.new([0x3042]),             # あ
    }
  end

  let(:index) { described_class.new(entries) }

  describe "#lookup" do
    it "returns the Set of codepoints for a language" do
      expect(index.lookup("en")).to eq(Set.new([97, 98, 99]))
      expect(index.lookup("fr")).to include(233)
    end

    it "returns nil for an unknown language" do
      expect(index.lookup("xx")).to be_nil
    end
  end

  describe "#include?" do
    it "returns true for known languages" do
      expect(index.include?("en")).to be true
      expect(index.include?("ja")).to be true
    end

    it "returns false for unknown languages" do
      expect(index.include?("xx")).to be false
    end
  end

  describe "#languages" do
    it "returns sorted language keys" do
      expect(index.languages).to eq(%w[en fr ja])
    end
  end

  describe "#size and #each" do
    it "reports the language count" do
      expect(index.size).to eq(3)
    end

    it "is enumerable" do
      expect(index.map { |lang, _set| lang }).to contain_exactly("en", "fr", "ja")
    end
  end

  describe "constructor flexibility" do
    it "accepts Array<Integer> values and coerces them to Sets" do
      index = described_class.new("de" => [97, 98, 99])
      expect(index.lookup("de")).to eq(Set.new([97, 98, 99]))
    end

    it "accepts an empty hash" do
      expect(described_class.new.size).to eq(0)
      expect(described_class.new.languages).to eq([])
    end
  end

  describe "#save / .load round-trip" do
    it "round-trips through YAML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "languages.yml")
        index.save(path)
        loaded = described_class.load(path)

        expect(loaded.size).to eq(index.size)
        expect(loaded.languages).to eq(%w[en fr ja])
        expect(loaded.lookup("fr")).to eq(Set.new([97, 98, 99, 233]))
        expect(loaded.lookup("ja")).to eq(Set.new([0x3042]))
      end
    end

    it "writes YAML as sorted codepoint arrays per language" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "languages.yml")
        index.save(path)
        yaml = YAML.load_file(path)

        expect(yaml["en"]).to eq([97, 98, 99])
        expect(yaml["fr"]).to eq([97, 98, 99, 233])
      end
    end
  end
end
