# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/cldr"

RSpec.describe Fontisan::Models::Cldr::LanguageCoverage do
  let(:lc) do
    described_class.new(
      language: "en",
      covered: 25,
      total: 26,
      coverage_ratio: 0.9615,
      fully_supported: false,
    )
  end

  it "exposes the language code" do
    expect(lc.language).to eq("en")
  end

  it "exposes covered count" do
    expect(lc.covered).to eq(25)
  end

  it "exposes total count" do
    expect(lc.total).to eq(26)
  end

  it "exposes coverage_ratio" do
    expect(lc.coverage_ratio).to eq(0.9615)
  end

  it "exposes fully_supported" do
    expect(lc.fully_supported).to be false
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(lc.to_yaml)
    expect(restored.language).to eq("en")
    expect(restored.covered).to eq(25)
    expect(restored.total).to eq(26)
    expect(restored.coverage_ratio).to eq(0.9615)
    expect(restored.fully_supported).to be(false)
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(lc.to_json)
    expect(restored.language).to eq("en")
    expect(restored.total).to eq(26)
    expect(restored.fully_supported).to be(false)
  end

  it "round-trips the fully_supported=true case through YAML" do
    full = described_class.new(
      language: "fr",
      covered: 5,
      total: 5,
      coverage_ratio: 1.0,
      fully_supported: true,
    )
    restored = described_class.from_yaml(full.to_yaml)
    expect(restored.fully_supported).to be(true)
  end

  it "round-trips the empty exemplar set case (total == 0)" do
    empty = described_class.new(
      language: "xx",
      covered: 0,
      total: 0,
      coverage_ratio: 0.0,
      fully_supported: false,
    )
    restored = described_class.from_yaml(empty.to_yaml)
    expect(restored.total).to eq(0)
    expect(restored.fully_supported).to be(false)
  end
end
