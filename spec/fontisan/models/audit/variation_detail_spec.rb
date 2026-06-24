# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::VariationDetail do
  let(:axis) do
    Fontisan::Models::Audit::AuditAxis.new(
      tag: "wght",
      min_value: 100.0,
      default_value: 400.0,
      max_value: 900.0,
      name: "Weight",
    )
  end

  let(:instance) do
    Fontisan::Models::Audit::NamedInstance.new(
      subfamily_name: "Bold",
      postscript_name: "Foo-Bold",
      coordinates: "wght=700",
    )
  end

  let(:detail) do
    described_class.new(
      axes: [axis],
      named_instances: [instance],
      has_avar: true,
      has_cvar: false,
      has_hvar: true,
      has_vvar: false,
      has_mvar: false,
      has_gvar: false,
    )
  end

  it "exposes axes collection" do
    expect(detail.axes).to be_an(Array)
    expect(detail.axes.first).to be_a(Fontisan::Models::Audit::AuditAxis)
    expect(detail.axes.first.tag).to eq("wght")
  end

  it "exposes named_instances collection" do
    expect(detail.named_instances.first).to be_a(Fontisan::Models::Audit::NamedInstance)
    expect(detail.named_instances.first.subfamily_name).to eq("Bold")
  end

  it "exposes side-table presence flags" do
    expect(detail.has_avar).to be true
    expect(detail.has_cvar).to be false
    expect(detail.has_hvar).to be true
    expect(detail.has_vvar).to be false
    expect(detail.has_mvar).to be false
    expect(detail.has_gvar).to be false
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(detail.to_yaml)
    expect(restored.axes.first.tag).to eq("wght")
    expect(restored.named_instances.first.subfamily_name).to eq("Bold")
    expect(restored.has_avar).to be true
    expect(restored.has_gvar).to be false
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(detail.to_json)
    expect(restored.axes.first.tag).to eq("wght")
    expect(restored.has_hvar).to be true
  end

  it "constructs without raising when fields are unset" do
    expect { described_class.new }.not_to raise_error
  end
end
