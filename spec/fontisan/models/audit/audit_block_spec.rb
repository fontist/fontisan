# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/audit_block"

RSpec.describe Fontisan::Models::Audit::AuditBlock do
  subject(:block) do
    described_class.new(
      name: "Basic Latin",
      first_cp: 0x0000,
      last_cp: 0x007F,
      range: "U+0000–U+007F",
      total: 128,
      covered: 95,
      fill_ratio: 0.742,
      complete: false,
    )
  end

  describe "attributes" do
    it "exposes name" do
      expect(block.name).to eq("Basic Latin")
    end

    it "exposes first_cp / last_cp" do
      expect(block.first_cp).to eq(0x0000)
      expect(block.last_cp).to eq(0x007F)
    end

    it "exposes range string" do
      expect(block.range).to eq("U+0000–U+007F")
    end

    it "exposes total / covered counts" do
      expect(block.total).to eq(128)
      expect(block.covered).to eq(95)
    end

    it "exposes fill_ratio" do
      expect(block.fill_ratio).to eq(0.742)
    end

    it "exposes complete flag" do
      expect(block.complete).to be false
    end
  end

  describe "round-trip serialization" do
    it "round-trips through YAML" do
      parsed = described_class.from_yaml(block.to_yaml)
      expect(parsed.name).to eq("Basic Latin")
      expect(parsed.first_cp).to eq(0x0000)
      expect(parsed.last_cp).to eq(0x007F)
      expect(parsed.range).to eq("U+0000–U+007F")
      expect(parsed.total).to eq(128)
      expect(parsed.covered).to eq(95)
      expect(parsed.fill_ratio).to eq(0.742)
      expect(parsed.complete).to be false
    end

    it "round-trips through JSON preserving boolean complete flag" do
      complete_block = described_class.new(
        name: "Basic Latin", first_cp: 0, last_cp: 0x7F,
        range: "U+0000–U+007F", total: 128, covered: 128,
        fill_ratio: 1.0, complete: true
      )
      parsed = described_class.from_json(complete_block.to_json)
      expect(parsed.complete).to be true
      expect(parsed.fill_ratio).to eq(1.0)
    end

    it "preserves wire names declared in the mapping" do
      yaml = block.to_yaml
      expect(yaml).to include("first_cp:")
      expect(yaml).to include("last_cp:")
      expect(yaml).to include("fill_ratio:")
    end
  end

  describe "with a fully-covered block" do
    it "marks complete=true when covered == total" do
      full = described_class.new(
        name: "Latin-1 Supplement", first_cp: 0x80, last_cp: 0xFF,
        range: "U+0080–U+00FF", total: 128, covered: 128,
        fill_ratio: 1.0, complete: true
      )
      expect(full.complete).to be true
      expect(full.fill_ratio).to eq(1.0)
    end
  end
end
