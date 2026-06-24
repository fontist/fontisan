# frozen_string_literal: true

require "spec_helper"
require "fontisan/models/audit/metrics"

RSpec.describe Fontisan::Models::Audit::Metrics do
  describe "round-trip serialization" do
    let(:attrs) do
      {
        units_per_em: 2048,
        bbox_x_min: -1024,
        bbox_y_min: -1024,
        bbox_x_max: 2048,
        bbox_y_max: 2048,
        hhea_ascent: 2048,
        hhea_descent: -512,
        hhea_line_gap: 0,
        typo_ascender: 2048,
        typo_descender: -512,
        typo_line_gap: 0,
        win_ascent: 2200,
        win_descent: 600,
        x_height: 1080,
        cap_height: 1500,
        underline_position: -100.0,
        underline_thickness: 50.0,
      }
    end

    it "round-trips through YAML" do
      model = described_class.new(**attrs)
      parsed = described_class.from_yaml(model.to_yaml)
      expect(parsed.units_per_em).to eq(2048)
      expect(parsed.underline_thickness).to eq(50.0)
    end

    it "round-trips through JSON" do
      model = described_class.new(**attrs)
      parsed = described_class.from_json(model.to_json)
      expect(parsed.hhea_ascent).to eq(2048)
      expect(parsed.typo_descender).to eq(-512)
    end
  end

  describe "#metrics_consistent?" do
    it "returns true when hhea and typo ascent/descent match" do
      model = described_class.new(
        hhea_ascent: 2048, hhea_descent: -512,
        typo_ascender: 2048, typo_descender: -512
      )
      expect(model.metrics_consistent?).to be true
    end

    it "returns false when hhea and typo ascent differ" do
      model = described_class.new(
        hhea_ascent: 2048, hhea_descent: -512,
        typo_ascender: 2100, typo_descender: -512
      )
      expect(model.metrics_consistent?).to be false
    end

    it "returns false when hhea and typo descent differ" do
      model = described_class.new(
        hhea_ascent: 2048, hhea_descent: -512,
        typo_ascender: 2048, typo_descender: -600
      )
      expect(model.metrics_consistent?).to be false
    end

    it "returns false when any required field is nil" do
      expect(described_class.new.metrics_consistent?).to be false
    end
  end

  describe "with all-nil fields" do
    it "constructs without raising" do
      expect { described_class.new }.not_to raise_error
    end
  end
end
