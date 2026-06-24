# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::FieldChange do
  let(:change) do
    described_class.new(field: "weight_class", left: "400", right: "700")
  end

  it "exposes the field name" do
    expect(change.field).to eq("weight_class")
  end

  it "exposes the left value" do
    expect(change.left).to eq("400")
  end

  it "exposes the right value" do
    expect(change.right).to eq("700")
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(change.to_yaml)
    expect(restored.field).to eq("weight_class")
    expect(restored.left).to eq("400")
    expect(restored.right).to eq("700")
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(change.to_json)
    expect(restored.right).to eq("700")
  end

  it "round-trips an empty left value (nil field on Type 1)" do
    # lutaml-model treats empty strings as nil on round-trip; the differ
    # uses "" to mean "missing", and from_yaml restores that as nil.
    nil_change = described_class.new(field: "weight_class", left: "", right: "400")
    restored = described_class.from_yaml(nil_change.to_yaml)
    expect(restored.right).to eq("400")
    expect(restored.left).to be_nil.or eq("")
  end
end
