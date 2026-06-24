# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::ScriptCoverageRow do
  let(:row) do
    described_class.new(
      script: "Cyrillic",
      face_count: 3,
      faces: %w[A-Regular B-Regular C-Bold],
    )
  end

  it "exposes the script, count, and faces" do
    expect(row.script).to eq("Cyrillic")
    expect(row.face_count).to eq(3)
    expect(row.faces).to eq(%w[A-Regular B-Regular C-Bold])
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(row.to_yaml)
    expect(restored.script).to eq("Cyrillic")
    expect(restored.face_count).to eq(3)
    expect(restored.faces).to eq(%w[A-Regular B-Regular C-Bold])
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(row.to_json)
    expect(restored.face_count).to eq(3)
    expect(restored.faces.length).to eq(3)
  end
end
