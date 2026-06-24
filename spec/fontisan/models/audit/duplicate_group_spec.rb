# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::DuplicateGroup do
  let(:group) do
    described_class.new(
      source_sha256: "deadbeef",
      files: ["/lib/a.ttf", "/lib/b.ttf", "/lib/c.ttf"],
    )
  end

  it "exposes the sha and file list" do
    expect(group.source_sha256).to eq("deadbeef")
    expect(group.files.length).to eq(3)
  end

  it "round-trips through YAML" do
    restored = described_class.from_yaml(group.to_yaml)
    expect(restored.source_sha256).to eq("deadbeef")
    expect(restored.files).to eq(["/lib/a.ttf", "/lib/b.ttf", "/lib/c.ttf"])
  end

  it "round-trips through JSON" do
    restored = described_class.from_json(group.to_json)
    expect(restored.files.length).to eq(3)
  end
end
