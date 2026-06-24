# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::OpenTypeLayout do
  let(:by_script) do
    [
      Fontisan::Models::Audit::ScriptFeatures.new(
        script: "latn",
        gsub_features: ["liga"],
        gpos_features: ["kern"],
      ),
      Fontisan::Models::Audit::ScriptFeatures.new(
        script: "cyrl",
        gsub_features: ["liga"],
        gpos_features: [],
      ),
    ]
  end

  let(:layout) do
    described_class.new(
      scripts: %w[cyrl latn],
      features: %w[kern liga],
      by_script: by_script,
      has_gsub: true,
      has_gpos: true,
    )
  end

  it "exposes scripts collection" do
    expect(layout.scripts).to eq(%w[cyrl latn])
  end

  it "exposes features collection" do
    expect(layout.features).to eq(%w[kern liga])
  end

  it "exposes by_script collection" do
    expect(layout.by_script.length).to eq(2)
    expect(layout.by_script.first).to be_a(Fontisan::Models::Audit::ScriptFeatures)
  end

  it "exposes presence flags" do
    expect(layout.has_gsub).to be true
    expect(layout.has_gpos).to be true
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(layout.to_yaml)
    expect(restored.scripts).to eq(%w[cyrl latn])
    expect(restored.features).to eq(%w[kern liga])
    expect(restored.by_script.length).to eq(2)
    expect(restored.by_script.map(&:script)).to eq(%w[latn cyrl])
    expect(restored.has_gsub).to be true
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(layout.to_json)
    expect(restored.scripts).to eq(%w[cyrl latn])
    expect(restored.by_script.first.gsub_features).to eq(["liga"])
  end

  it "constructs without raising when fields are unset" do
    expect { described_class.new }.not_to raise_error
  end
end
