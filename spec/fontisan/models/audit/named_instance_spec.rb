# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::NamedInstance do
  describe "format_coordinates" do
    it "returns nil when axis_tags is nil" do
      expect(described_class.format_coordinates(nil, [400])).to be_nil
    end

    it "returns nil when values is nil" do
      expect(described_class.format_coordinates(["wght"], nil)).to be_nil
    end

    it "returns nil when axis_tags is empty" do
      expect(described_class.format_coordinates([], [400])).to be_nil
    end

    it "returns nil when values is empty" do
      expect(described_class.format_coordinates(["wght"], [])).to be_nil
    end

    it "formats a single axis" do
      result = described_class.format_coordinates(["wght"], [700])
      expect(result).to eq("wght=700")
    end

    it "formats multiple axes in tag order" do
      result = described_class.format_coordinates(%w[wght wdth], [700, 100])
      expect(result).to eq("wght=700,wdth=100")
    end

    it "zips shorter arrays" do
      result = described_class.format_coordinates(%w[wght wdth ital], [700])
      expect(result).to eq("wght=700,wdth=,ital=")
    end
  end

  describe "round-trip" do
    let(:instance) do
      described_class.new(
        subfamily_name: "Bold",
        postscript_name: "Foo-Bold",
        coordinates: "wght=700,wdth=100",
      )
    end

    it "round-trips through YAML" do
      restored = described_class.from_yaml(instance.to_yaml)
      expect(restored.subfamily_name).to eq("Bold")
      expect(restored.postscript_name).to eq("Foo-Bold")
      expect(restored.coordinates).to eq("wght=700,wdth=100")
    end

    it "round-trips through JSON" do
      restored = described_class.from_json(instance.to_json)
      expect(restored.subfamily_name).to eq("Bold")
      expect(restored.coordinates).to eq("wght=700,wdth=100")
    end
  end
end
