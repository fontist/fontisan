# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/gasp_range"

RSpec.describe Fontisan::Models::Audit::GaspRange do
  describe ".from_flags bit decoding" do
    it "decodes a flags=0 range as all-false" do
      range = described_class.from_flags(8, 0)
      expect(range.max_ppem).to eq(8)
      expect(range.gridfit).to be false
      expect(range.do_gray).to be false
      expect(range.symmetric_gridfit).to be false
      expect(range.symmetric_smoothing).to be false
    end

    it "decodes gridfit (bit 0)" do
      range = described_class.from_flags(7, 0x0001)
      expect(range.gridfit).to be true
      expect(range.do_gray).to be false
    end

    it "decodes do_gray (bit 1)" do
      range = described_class.from_flags(7, 0x0002)
      expect(range.do_gray).to be true
    end

    it "decodes symmetric_gridfit (bit 2)" do
      range = described_class.from_flags(7, 0x0004)
      expect(range.symmetric_gridfit).to be true
    end

    it "decodes symmetric_smoothing (bit 3)" do
      range = described_class.from_flags(7, 0x0008)
      expect(range.symmetric_smoothing).to be true
    end

    it "decodes combined flags" do
      range = described_class.from_flags(65535, 0x000F)
      expect(range.gridfit).to be true
      expect(range.do_gray).to be true
      expect(range.symmetric_gridfit).to be true
      expect(range.symmetric_smoothing).to be true
    end

    it "ignores reserved high bits" do
      range = described_class.from_flags(8, 0xFFFF)
      expect(range.gridfit).to be true
      expect(range.do_gray).to be true
      expect(range.symmetric_gridfit).to be true
      expect(range.symmetric_smoothing).to be true
    end
  end

  describe "#gridfit_and_smoothing?" do
    it "is true when both gridfit and do_gray are set" do
      expect(described_class.from_flags(8, 0x0003).gridfit_and_smoothing?).to be true
    end

    it "is false when only gridfit is set" do
      expect(described_class.from_flags(8, 0x0001).gridfit_and_smoothing?).to be false
    end

    it "is false when only do_gray is set" do
      expect(described_class.from_flags(8, 0x0002).gridfit_and_smoothing?).to be false
    end
  end

  describe "round-trip serialization" do
    it "round-trips through YAML" do
      range = described_class.from_flags(12, 0x0003)
      parsed = described_class.from_yaml(range.to_yaml)
      expect(parsed.max_ppem).to eq(12)
      expect(parsed.gridfit).to be true
      expect(parsed.do_gray).to be true
    end

    it "round-trips through JSON" do
      range = described_class.from_flags(12, 0x000C)
      parsed = described_class.from_json(range.to_json)
      expect(parsed.max_ppem).to eq(12)
      expect(parsed.symmetric_gridfit).to be true
      expect(parsed.symmetric_smoothing).to be true
    end
  end
end
