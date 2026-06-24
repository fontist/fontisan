# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit"

RSpec.describe Fontisan::Models::Audit::CodepointRange do
  describe "#to_s" do
    it "renders a single codepoint without a dash" do
      r = described_class.new(first_cp: 0x0041, last_cp: 0x0041)
      expect(r.to_s).to eq("U+0041")
    end

    it "renders a true range with a dash" do
      r = described_class.new(first_cp: 0x0041, last_cp: 0x005A)
      expect(r.to_s).to eq("U+0041-U+005A")
    end

    it "zero-pads to at least 4 hex digits" do
      r = described_class.new(first_cp: 0x0020, last_cp: 0x007E)
      expect(r.to_s).to eq("U+0020-U+007E")
    end

    it "handles codepoints above 0xFFFF" do
      r = described_class.new(first_cp: 0x1F300, last_cp: 0x1F320)
      expect(r.to_s).to eq("U+1F300-U+1F320")
    end
  end

  describe "round-trip" do
    it "round-trips through YAML" do
      r = described_class.new(first_cp: 0x0041, last_cp: 0x005A)
      restored = described_class.from_yaml(r.to_yaml)
      expect(restored.first_cp).to eq(0x0041)
      expect(restored.last_cp).to eq(0x005A)
    end

    it "round-trips through JSON" do
      r = described_class.new(first_cp: 0x1F300, last_cp: 0x1F320)
      restored = described_class.from_json(r.to_json)
      expect(restored.first_cp).to eq(0x1F300)
    end
  end
end
