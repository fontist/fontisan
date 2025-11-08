# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::GlyphInfo do
  describe "#initialize" do
    it "creates a new GlyphInfo instance" do
      glyph_info = described_class.new
      expect(glyph_info).to be_a(described_class)
    end
  end

  describe "attributes" do
    let(:glyph_info) do
      described_class.new.tap do |info|
        info.glyph_count = 258
        info.glyph_names = [".notdef", "space", "exclam"]
        info.source = "post_1.0"
      end
    end

    it "has glyph_count attribute" do
      expect(glyph_info.glyph_count).to eq(258)
    end

    it "has glyph_names attribute" do
      expect(glyph_info.glyph_names).to eq([".notdef", "space", "exclam"])
    end

    it "has source attribute" do
      expect(glyph_info.source).to eq("post_1.0")
    end
  end

  describe "serialization" do
    let(:glyph_info) do
      described_class.new.tap do |info|
        info.glyph_count = 3
        info.glyph_names = [".notdef", "space", "exclam"]
        info.source = "post_2.0"
      end
    end

    describe "#to_yaml" do
      it "serializes to YAML" do
        yaml = glyph_info.to_yaml
        expect(yaml).to include("glyph_count: 3")
        expect(yaml).to include("source: post_2.0")
        expect(yaml).to include("glyph_names:")
        expect(yaml).to include("- \".notdef\"")
        expect(yaml).to include("- space")
        expect(yaml).to include("- exclam")
      end
    end

    describe "#to_json" do
      it "serializes to JSON" do
        json = glyph_info.to_json
        parsed = JSON.parse(json)
        expect(parsed["glyph_count"]).to eq(3)
        expect(parsed["source"]).to eq("post_2.0")
        expect(parsed["glyph_names"]).to eq([".notdef", "space", "exclam"])
      end
    end

    describe "YAML round-trip" do
      it "deserializes from YAML" do
        yaml = glyph_info.to_yaml
        loaded = described_class.from_yaml(yaml)
        expect(loaded.glyph_count).to eq(3)
        expect(loaded.source).to eq("post_2.0")
        expect(loaded.glyph_names).to eq([".notdef", "space", "exclam"])
      end
    end

    describe "JSON round-trip" do
      it "deserializes from JSON" do
        json = glyph_info.to_json
        loaded = described_class.from_json(json)
        expect(loaded.glyph_count).to eq(3)
        expect(loaded.source).to eq("post_2.0")
        expect(loaded.glyph_names).to eq([".notdef", "space", "exclam"])
      end
    end
  end

  describe "with empty glyph names" do
    let(:glyph_info) do
      described_class.new.tap do |info|
        info.glyph_count = 0
        info.glyph_names = []
        info.source = "none"
      end
    end

    it "handles empty glyph names" do
      expect(glyph_info.glyph_count).to eq(0)
      expect(glyph_info.glyph_names).to be_empty
      expect(glyph_info.source).to eq("none")
    end

    it "serializes empty glyph names to YAML" do
      yaml = glyph_info.to_yaml
      expect(yaml).to include("glyph_count: 0")
      expect(yaml).to include("source: none")
      # lutaml-model omits empty collections from YAML output
    end

    it "serializes empty glyph names to JSON" do
      json = glyph_info.to_json
      parsed = JSON.parse(json)
      expect(parsed["glyph_count"]).to eq(0)
      expect(parsed["source"]).to eq("none")
      # lutaml-model omits empty collections from JSON output
      expect(parsed["glyph_names"]).to be_nil
    end
  end
end
