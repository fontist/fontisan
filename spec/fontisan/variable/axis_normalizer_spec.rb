# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/axis_normalizer"
require "fontisan/tables/fvar"

RSpec.describe Fontisan::Variable::AxisNormalizer do
  let(:fvar_data) do
    # Build minimal fvar table data
    data = "".b
    data << [1, 0].pack("n2") # major, minor version
    data << [16].pack("n") # axes array offset
    data << [0].pack("n") # reserved
    data << [2].pack("n") # axis count
    data << [20].pack("n") # axis size
    data << [0].pack("n") # instance count
    data << [0].pack("n") # instance size

    # Axis 1: wght (weight) - 400 to 700, default 400
    data << "wght" # axis tag
    data << [(400.0 * 65536).to_i].pack("N") # min (Fixed)
    data << [(400.0 * 65536).to_i].pack("N") # default
    data << [(700.0 * 65536).to_i].pack("N") # max
    data << [0].pack("n") # flags
    data << [256].pack("n") # name ID

    # Axis 2: wdth (width) - 75 to 125, default 100
    data << "wdth" # axis tag
    data << [(75.0 * 65536).to_i].pack("N") # min
    data << [(100.0 * 65536).to_i].pack("N") # default
    data << [(125.0 * 65536).to_i].pack("N") # max
    data << [0].pack("n") # flags
    data << [257].pack("n") # name ID

    data
  end

  let(:fvar) { Fontisan::Tables::Fvar.read(fvar_data) }
  let(:normalizer) { described_class.new(fvar) }

  describe "#initialize" do
    it "creates normalizer with fvar table" do
      expect(normalizer).to be_a(described_class)
    end

    it "builds axis map from fvar" do
      expect(normalizer.axis_tags).to include("wght", "wdth")
    end

    it "loads configuration" do
      expect(normalizer.config).to be_a(Hash)
    end
  end

  describe "#normalize" do
    context "with default values" do
      it "returns 0.0 for default wght" do
        result = normalizer.normalize({ "wght" => 400 })
        expect(result["wght"]).to eq(0.0)
      end

      it "returns 0.0 for default wdth" do
        result = normalizer.normalize({ "wdth" => 100 })
        expect(result["wdth"]).to eq(0.0)
      end
    end

    context "with values above default" do
      it "normalizes wght=700 to 1.0" do
        result = normalizer.normalize({ "wght" => 700 })
        expect(result["wght"]).to eq(1.0)
      end

      it "normalizes wght=550 to 0.5" do
        result = normalizer.normalize({ "wght" => 550 })
        expect(result["wght"]).to eq(0.5)
      end

      it "normalizes wdth=125 to 1.0" do
        result = normalizer.normalize({ "wdth" => 125 })
        expect(result["wdth"]).to eq(1.0)
      end

      it "normalizes wdth=112.5 to 0.5" do
        result = normalizer.normalize({ "wdth" => 112.5 })
        expect(result["wdth"]).to eq(0.5)
      end
    end

    context "with values below default" do
      it "normalizes wght=400 at min to 0.0" do
        result = normalizer.normalize({ "wght" => 400 })
        expect(result["wght"]).to eq(0.0)
      end

      it "normalizes wdth=75 to -1.0" do
        result = normalizer.normalize({ "wdth" => 75 })
        expect(result["wdth"]).to eq(-1.0)
      end

      it "normalizes wdth=87.5 to -0.5" do
        result = normalizer.normalize({ "wdth" => 87.5 })
        expect(result["wdth"]).to eq(-0.5)
      end
    end

    context "with multiple axes" do
      it "normalizes both axes" do
        result = normalizer.normalize({ "wght" => 550, "wdth" => 112.5 })
        expect(result["wght"]).to eq(0.5)
        expect(result["wdth"]).to eq(0.5)
      end
    end

    context "with missing coordinates" do
      it "uses default values when use_axis_defaults is true" do
        result = normalizer.normalize({})
        expect(result["wght"]).to eq(0.0)
        expect(result["wdth"]).to eq(0.0)
      end

      it "omits axes when coordinate not provided and defaults disabled" do
        config = { coordinate_normalization: { use_axis_defaults: false } }
        normalizer_no_defaults = described_class.new(fvar, config)
        result = normalizer_no_defaults.normalize({})
        expect(result).to be_empty
      end
    end

    context "with out-of-range values" do
      it "clamps value above max when clamp_coordinates is true" do
        result = normalizer.normalize({ "wght" => 800 })
        expect(result["wght"]).to eq(1.0)
      end

      it "clamps value below min when clamp_coordinates is true" do
        result = normalizer.normalize({ "wdth" => 50 })
        expect(result["wdth"]).to eq(-1.0)
      end
    end
  end

  describe "#normalize_axis" do
    it "normalizes single axis value" do
      result = normalizer.normalize_axis(550, "wght")
      expect(result).to eq(0.5)
    end

    it "raises error for unknown axis" do
      expect do
        normalizer.normalize_axis(500, "unkn")
      end.to raise_error(ArgumentError, /Unknown axis/)
    end
  end

  describe "#axis_info" do
    it "returns axis information for wght" do
      info = normalizer.axis_info("wght")
      expect(info[:min]).to eq(400.0)
      expect(info[:default]).to eq(400.0)
      expect(info[:max]).to eq(700.0)
    end

    it "returns nil for unknown axis" do
      expect(normalizer.axis_info("unkn")).to be_nil
    end
  end

  describe "#axis_tags" do
    it "returns all axis tags" do
      tags = normalizer.axis_tags
      expect(tags).to contain_exactly("wght", "wdth")
    end
  end

  describe "precision" do
    it "rounds normalized values to configured precision" do
      result = normalizer.normalize({ "wght" => 401 })
      # Should round to 6 decimal places by default
      expect(result["wght"]).to be_within(0.000001).of(0.003333)
    end
  end

  describe "edge cases" do
    it "handles axis with same min and default" do
      # wght has min=default=400, so any value below should clamp to 0
      result = normalizer.normalize({ "wght" => 300 })
      expect(result["wght"]).to eq(0.0)
    end

    it "handles floating point coordinates" do
      result = normalizer.normalize({ "wght" => 550.5 })
      expect(result["wght"]).to be_between(0.5, 0.51)
    end

    it "handles symbol keys" do
      result = normalizer.normalize({ wght: 550 })
      expect(result["wght"]).to eq(0.5)
    end
  end
end
