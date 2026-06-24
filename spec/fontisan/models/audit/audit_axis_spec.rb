# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/audit_axis"

RSpec.describe Fontisan::Models::Audit::AuditAxis do
  subject(:axis) do
    described_class.new(
      tag: "wght",
      min_value: 100.0,
      default_value: 400.0,
      max_value: 900.0,
      name: "Weight",
    )
  end

  describe "attributes" do
    it "exposes tag" do
      expect(axis.tag).to eq("wght")
    end

    it "exposes min_value" do
      expect(axis.min_value).to eq(100.0)
    end

    it "exposes default_value" do
      expect(axis.default_value).to eq(400.0)
    end

    it "exposes max_value" do
      expect(axis.max_value).to eq(900.0)
    end

    it "exposes name" do
      expect(axis.name).to eq("Weight")
    end
  end

  describe "round-trip serialization" do
    it "round-trips through YAML" do
      parsed = described_class.from_yaml(axis.to_yaml)
      expect(parsed.tag).to eq("wght")
      expect(parsed.min_value).to eq(100.0)
      expect(parsed.default_value).to eq(400.0)
      expect(parsed.max_value).to eq(900.0)
      expect(parsed.name).to eq("Weight")
    end

    it "round-trips through JSON" do
      parsed = described_class.from_json(axis.to_json)
      expect(parsed.tag).to eq("wght")
      expect(parsed.default_value).to eq(400.0)
      expect(parsed.name).to eq("Weight")
    end

    it "uses the wire names declared in the mapping (not the Ruby attr names)" do
      yaml = axis.to_yaml
      expect(yaml).to include("min_value:")
      expect(yaml).to include("default_value:")
      expect(yaml).to include("max_value:")
    end
  end

  describe "with nil name" do
    it "serializes a nameless axis" do
      nameless = described_class.new(tag: "wdth", min_value: 75.0,
                                     default_value: 100.0, max_value: 125.0)
      parsed = described_class.from_yaml(nameless.to_yaml)
      expect(parsed.tag).to eq("wdth")
      expect(parsed.name).to be_nil
    end
  end
end
