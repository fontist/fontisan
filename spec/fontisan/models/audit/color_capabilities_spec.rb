# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/color_capabilities"

RSpec.describe Fontisan::Models::Audit::ColorCapabilities do
  describe ".derive_formats" do
    it "returns empty when nothing is present" do
      expect(described_class.derive_formats(has_colr: false, colr_version: nil,
                                            has_cpal: false, has_svg: false,
                                            has_cbdt: false, has_sbix: false)).to eq([])
    end

    it "returns colr_v0 for COLR v0" do
      result = described_class.derive_formats(has_colr: true, colr_version: 0,
                                              has_cpal: false, has_svg: false,
                                              has_cbdt: false, has_sbix: false)
      expect(result).to eq(["colr_v0"])
    end

    it "returns colr_v1 for COLR v1" do
      result = described_class.derive_formats(has_colr: true, colr_version: 1,
                                              has_cpal: false, has_svg: false,
                                              has_cbdt: false, has_sbix: false)
      expect(result).to eq(["colr_v1"])
    end

    it "combines multiple formats" do
      result = described_class.derive_formats(has_colr: true, colr_version: 1,
                                              has_cpal: true, has_svg: true,
                                              has_cbdt: true, has_sbix: true)
      expect(result).to eq(%w[colr_v1 cpal svg cbdt sbix])
    end

    it "treats unknown COLR version as v0" do
      result = described_class.derive_formats(has_colr: true, colr_version: nil,
                                              has_cpal: false, has_svg: false,
                                              has_cbdt: false, has_sbix: false)
      expect(result).to eq(["colr_v0"])
    end
  end

  describe "round-trip serialization" do
    let(:attrs) do
      {
        has_colr: true,
        colr_version: 1,
        colr_base_glyph_count: 1024,
        colr_layer_count: 2048,
        has_cpal: true,
        cpal_palette_count: 1,
        cpal_color_count: 16,
        has_svg: false,
        svg_document_count: nil,
        has_cbdt: true,
        has_cblc: true,
        cbdt_strike_count: 3,
        has_sbix: false,
        sbix_strike_count: nil,
        color_formats: %w[colr_v1 cpal cbdt],
      }
    end

    it "round-trips through YAML" do
      model = described_class.new(**attrs)
      parsed = described_class.from_yaml(model.to_yaml)
      expect(parsed.has_colr).to be true
      expect(parsed.colr_version).to eq(1)
      expect(parsed.colr_base_glyph_count).to eq(1024)
      expect(parsed.cpal_palette_count).to eq(1)
      expect(parsed.color_formats).to eq(%w[colr_v1 cpal cbdt])
    end

    it "round-trips through JSON" do
      model = described_class.new(**attrs)
      parsed = described_class.from_json(model.to_json)
      expect(parsed.has_cbdt).to be true
      expect(parsed.has_cblc).to be true
      expect(parsed.cbdt_strike_count).to eq(3)
      expect(parsed.color_formats).to eq(%w[colr_v1 cpal cbdt])
    end
  end

  describe "with all-nil fields" do
    it "constructs without raising" do
      expect { described_class.new }.not_to raise_error
    end
  end
end
