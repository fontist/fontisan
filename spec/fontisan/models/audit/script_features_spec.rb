# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::ScriptFeatures do
  let(:sf) do
    described_class.new(
      script: "latn",
      gsub_features: %w[liga dlig],
      gpos_features: ["kern"],
    )
  end

  it "exposes script tag" do
    expect(sf.script).to eq("latn")
  end

  it "exposes gsub_features collection" do
    expect(sf.gsub_features).to eq(%w[liga dlig])
  end

  it "exposes gpos_features collection" do
    expect(sf.gpos_features).to eq(["kern"])
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(sf.to_yaml)
    expect(restored.script).to eq("latn")
    expect(restored.gsub_features).to eq(%w[liga dlig])
    expect(restored.gpos_features).to eq(["kern"])
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(sf.to_json)
    expect(restored.script).to eq("latn")
    expect(restored.gpos_features).to eq(["kern"])
  end

  it "preserves trailing-space script tags" do
    sf = described_class.new(script: "kana ", gsub_features: [], gpos_features: [])
    restored = described_class.from_yaml(sf.to_yaml)
    expect(restored.script).to eq("kana ")
  end
end
