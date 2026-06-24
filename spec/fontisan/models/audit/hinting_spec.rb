# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/hinting"

RSpec.describe Fontisan::Models::Audit::Hinting do
  describe ".derive_flags" do
    it "returns unhinted + none when nothing is present" do
      result = described_class.derive_flags(has_tt: false, has_cff: false,
                                            has_gasp: false)
      expect(result[:is_unhinted]).to be true
      expect(result[:hinting_format]).to eq("none")
    end

    it "returns truetype format when TT hinting is present" do
      result = described_class.derive_flags(has_tt: true, has_cff: false,
                                            has_gasp: false)
      expect(result[:is_unhinted]).to be false
      expect(result[:hinting_format]).to eq("truetype")
    end

    it "returns cff format when only CFF hinting is present" do
      result = described_class.derive_flags(has_tt: false, has_cff: true,
                                            has_gasp: false)
      expect(result[:is_unhinted]).to be false
      expect(result[:hinting_format]).to eq("cff")
    end

    it "returns truetype format when gasp present without TT programs" do
      result = described_class.derive_flags(has_tt: false, has_cff: false,
                                            has_gasp: true)
      expect(result[:is_unhinted]).to be false
      expect(result[:hinting_format]).to eq("truetype")
    end

    it "returns mixed format when both TT and CFF hinting present" do
      result = described_class.derive_flags(has_tt: true, has_cff: true,
                                            has_gasp: false)
      expect(result[:hinting_format]).to eq("mixed")
    end
  end

  describe "round-trip serialization" do
    let(:gasp_range) do
      Fontisan::Models::Audit::GaspRange.from_flags(8, 0x0003)
    end

    let(:attrs) do
      {
        has_fpgm: true,
        fpgm_instruction_count: 64,
        has_prep: true,
        prep_instruction_count: 32,
        has_cvt: true,
        cvt_entry_count: 16,
        has_cvar: false,
        gasp_ranges: [gasp_range],
        cff_has_private_dict: false,
        cff_hint_count: nil,
        is_unhinted: false,
        hinting_format: "truetype",
      }
    end

    it "round-trips through YAML" do
      model = described_class.new(**attrs)
      parsed = described_class.from_yaml(model.to_yaml)
      expect(parsed.has_fpgm).to be true
      expect(parsed.fpgm_instruction_count).to eq(64)
      expect(parsed.cvt_entry_count).to eq(16)
      expect(parsed.gasp_ranges.first.max_ppem).to eq(8)
      expect(parsed.hinting_format).to eq("truetype")
    end

    it "round-trips through JSON" do
      model = described_class.new(**attrs)
      parsed = described_class.from_json(model.to_json)
      expect(parsed.has_prep).to be true
      expect(parsed.cff_hint_count).to be_nil
      expect(parsed.gasp_ranges.first.do_gray).to be true
    end
  end

  describe "with all-nil fields" do
    it "constructs without raising" do
      expect { described_class.new }.not_to raise_error
    end
  end
end
