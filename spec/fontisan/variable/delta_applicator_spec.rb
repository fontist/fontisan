# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/delta_applicator"

RSpec.describe Fontisan::Variable::DeltaApplicator do
  # Create a mock font object with necessary tables
  let(:mock_font) do
    font = double("Font")

    # fvar table data
    fvar_data = build_fvar_data
    allow(font).to receive(:table_data).with("fvar").and_return(fvar_data)

    # Other tables return nil (not present)
    allow(font).to receive(:table_data).with("gvar").and_return(nil)
    allow(font).to receive(:table_data).with("HVAR").and_return(build_hvar_data)
    allow(font).to receive(:table_data).with("VVAR").and_return(nil)
    allow(font).to receive(:table_data).with("MVAR").and_return(nil)

    font
  end

  let(:applicator) { described_class.new(mock_font) }

  def build_fvar_data
    data = "".b
    data << [1, 0].pack("n2") # version
    data << [16].pack("n") # axes array offset
    data << [0].pack("n") # reserved
    data << [1].pack("n") # axis count
    data << [20].pack("n") # axis size
    data << [0].pack("n") # instance count
    data << [0].pack("n") # instance size

    # Axis: wght 400-700
    data << "wght"
    data << [(400.0 * 65536).to_i].pack("N")
    data << [(400.0 * 65536).to_i].pack("N")
    data << [(700.0 * 65536).to_i].pack("N")
    data << [0, 256].pack("n2")

    data
  end

  def build_hvar_data
    # Build HVAR with ItemVariationStore
    data = "".b
    data << [1, 0].pack("n2") # version (bytes 0-3)
    data << [20].pack("N") # store offset at 20 (bytes 4-7)
    data << [0, 0, 0].pack("N3") # mappings (none) (bytes 8-19)

    # ItemVariationStore at offset 20
    data << [1].pack("n") # format (bytes 0-1 within store)
    data << [16].pack("N") # region list offset within store (bytes 2-5)
    data << [1].pack("n") # data count (bytes 6-7)
    data << [26].pack("N") # data offset within store (bytes 8-11)
    # Padding from byte 12 to byte 16 (4 bytes)
    data << "\x00\x00\x00\x00"

    # Region list at store offset 16 (absolute offset 36, bytes 16-25 within store)
    data << [1].pack("n") # axis count
    data << [1].pack("n") # region count
    data << [0, 16384, 16384].pack("s>3") # start, peak, end

    # ItemVariationData at store offset 26 (absolute offset 46, bytes 26+ within store)
    data << [2].pack("n") # item count
    data << [1].pack("n") # short delta count
    data << [1].pack("n") # region index count
    data << [0].pack("n") # region index
    data << [10, 20].pack("s>2") # deltas for 2 items

    data
  end

  describe "#initialize" do
    it "creates applicator with font" do
      expect(applicator).to be_a(described_class)
    end

    it "initializes axis normalizer" do
      expect(applicator.axis_normalizer).to be_a(Fontisan::Variable::AxisNormalizer)
    end

    it "initializes region matcher" do
      expect(applicator.region_matcher).to be_a(Fontisan::Variable::RegionMatcher)
    end

    it "initializes metric delta processor" do
      expect(applicator.metric_delta_processor).to be_a(Fontisan::Variable::MetricDeltaProcessor)
    end

    it "raises error for non-variable font" do
      non_var_font = double("Font")
      allow(non_var_font).to receive(:table_data).and_return(nil)

      applicator_non_var = described_class.new(non_var_font)
      expect do
        applicator_non_var.apply({ "wght" => 700 })
      end.to raise_error(ArgumentError, /not a variable font/)
    end
  end

  describe "#variable_font?" do
    it "returns true when fvar is present" do
      expect(applicator.variable_font?).to be true
    end

    it "returns false when fvar is not present" do
      non_var_font = double("Font")
      allow(non_var_font).to receive(:table_data).and_return(nil)

      applicator_non_var = described_class.new(non_var_font)
      expect(applicator_non_var.variable_font?).to be false
    end
  end

  describe "#axes" do
    it "returns axis information" do
      axes_info = applicator.axes
      expect(axes_info).to have_key("wght")
      expect(axes_info["wght"][:min]).to eq(400.0)
      expect(axes_info["wght"][:max]).to eq(700.0)
    end
  end

  describe "#axis_tags" do
    it "returns all axis tags" do
      tags = applicator.axis_tags
      expect(tags).to include("wght")
    end
  end

  describe "#region_count" do
    it "returns number of variation regions" do
      count = applicator.region_count
      expect(count).to be >= 0
    end
  end

  describe "#apply" do
    it "normalizes user coordinates" do
      result = applicator.apply({ "wght" => 550 })
      expect(result[:normalized_coords]).to have_key("wght")
      expect(result[:normalized_coords]["wght"]).to eq(0.5)
    end

    it "calculates region scalars" do
      result = applicator.apply({ "wght" => 550 })
      expect(result[:region_scalars]).to be_an(Array)
    end

    it "includes user coordinates in result" do
      result = applicator.apply({ "wght" => 550 })
      expect(result[:user_coords]).to eq({ "wght" => 550 })
    end

    it "returns empty metric deltas when no variation tables" do
      result = applicator.apply({ "wght" => 550 })
      expect(result[:metric_deltas]).to eq({})
    end

    it "returns empty font metrics when no MVAR" do
      result = applicator.apply({ "wght" => 550 })
      expect(result[:font_metrics]).to eq({})
    end
  end

  describe "#apply_glyph" do
    it "applies deltas to specific glyph" do
      result = applicator.apply_glyph(0, { "wght" => 550 })
      expect(result).to have_key(:glyph_id)
      expect(result[:glyph_id]).to eq(0)
    end

    it "includes normalized coordinates" do
      result = applicator.apply_glyph(0, { "wght" => 550 })
      expect(result[:normalized_coords]).to have_key("wght")
    end

    it "includes metric deltas" do
      result = applicator.apply_glyph(0, { "wght" => 550 })
      expect(result).to have_key(:metric_deltas)
    end
  end

  describe "#apply_glyphs" do
    it "applies deltas to multiple glyphs" do
      result = applicator.apply_glyphs([0, 1], { "wght" => 550 })
      expect(result).to have_key(0)
      expect(result).to have_key(1)
    end

    it "returns metric deltas for each glyph" do
      result = applicator.apply_glyphs([0, 1], { "wght" => 550 })
      expect(result[0]).to have_key(:metric_deltas)
      expect(result[1]).to have_key(:metric_deltas)
    end
  end

  describe "#advance_width_delta" do
    it "returns advance width delta for glyph" do
      delta = applicator.advance_width_delta(0, { "wght" => 700 })
      # With region scalar 1.0 and delta 10
      expect(delta).to be_a(Integer)
    end

    it "scales delta by coordinates" do
      delta_half = applicator.advance_width_delta(0, { "wght" => 550 })
      delta_full = applicator.advance_width_delta(0, { "wght" => 700 })

      # Half way should give roughly half the delta
      expect(delta_half.abs).to be <= delta_full.abs
    end
  end

  describe "integration with all processors" do
    it "coordinates normalization and region matching" do
      result = applicator.apply({ "wght" => 550 })

      # Should have gone through normalization
      expect(result[:normalized_coords]["wght"]).to eq(0.5)

      # Should have calculated region scalars
      expect(result[:region_scalars]).not_to be_empty
    end

    it "handles default coordinates" do
      result = applicator.apply({ "wght" => 400 })
      expect(result[:normalized_coords]["wght"]).to eq(0.0)
    end

    it "handles maximum coordinates" do
      result = applicator.apply({ "wght" => 700 })
      expect(result[:normalized_coords]["wght"]).to eq(1.0)
    end
  end

  describe "edge cases" do
    it "handles empty coordinates" do
      result = applicator.apply({})
      expect(result[:normalized_coords]).not_to be_empty
    end

    it "handles out-of-range coordinates" do
      result = applicator.apply({ "wght" => 800 })
      # Should clamp to 1.0
      expect(result[:normalized_coords]["wght"]).to eq(1.0)
    end

    it "handles unknown axis tags" do
      result = applicator.apply({ "unkn" => 500 })
      expect(result[:normalized_coords]).not_to have_key("unkn")
    end
  end

  describe "configuration" do
    it "loads configuration from file" do
      expect(applicator.config).to be_a(Hash)
    end

    it "can be customized with config overrides" do
      custom_config = { validation: { validate_tables: false } }
      custom_applicator = described_class.new(mock_font, custom_config)
      expect(custom_applicator.config[:validation][:validate_tables]).to be false
    end
  end
end
