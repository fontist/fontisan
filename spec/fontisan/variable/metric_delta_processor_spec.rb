# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/metric_delta_processor"
require "fontisan/tables/hvar"
require "fontisan/tables/mvar"

RSpec.describe Fontisan::Variable::MetricDeltaProcessor do
  let(:item_var_store_data) do
    # Build ItemVariationStore with one region
    data = "".b
    data << [1].pack("n") # format (bytes 0-1)
    data << [16].pack("N") # region list offset (bytes 2-5)
    data << [1].pack("n") # data count (bytes 6-7)
    data << [26].pack("N") # data offset (bytes 8-11)
    # Padding from byte 12 to byte 16 (4 bytes)
    data << "\x00\x00\x00\x00"

    # Variation region list at offset 16 (bytes 16-25)
    data << [1].pack("n") # axis count
    data << [1].pack("n") # region count
    data << [0].pack("s>") # start
    data << [(1.0 * 16384).to_i].pack("s>") # peak
    data << [(1.0 * 16384).to_i].pack("s>") # end

    # ItemVariationData at offset 26 (bytes 26+)
    data << [3].pack("n") # item count (3 glyphs)
    data << [1].pack("n") # short delta count
    data << [1].pack("n") # region index count
    data << [0].pack("n") # region index 0
    # Delta values for 3 items
    data << [10].pack("s>") # glyph 0 delta: +10
    data << [20].pack("s>") # glyph 1 delta: +20
    data << [-5].pack("s>") # glyph 2 delta: -5

    data
  end

  let(:hvar_data) do
    # Build HVAR table
    data = "".b
    data << [1, 0].pack("n2") # major, minor version (bytes 0-3)
    data << [20].pack("N") # item variation store offset (bytes 4-7) - after 20 byte header
    data << [0].pack("N") # advance width mapping (bytes 8-11)
    data << [0].pack("N") # lsb mapping (bytes 12-15)
    data << [0].pack("N") # rsb mapping (bytes 16-19)

    # ItemVariationStore at offset 20
    data << item_var_store_data

    data
  end

  let(:mvar_data) do
    # Build MVAR table with one metric
    data = "".b
    data << [1, 0].pack("n2") # major, minor version (bytes 0-3)
    data << [0].pack("n") # reserved (bytes 4-5)
    data << [12].pack("n") # value record size (bytes 6-7)
    data << [1].pack("n") # value record count (bytes 8-9)
    data << [26].pack("N") # item variation store offset (bytes 10-13)

    # Value record at offset 14 (bytes 14-25, 12 bytes total)
    data << "hasc" # value tag (horizontal ascender) - 4 bytes
    data << [0].pack("N") # delta set outer index - 4 bytes
    data << [0].pack("N") # delta set inner index - 4 bytes

    # ItemVariationStore at offset 26
    data << item_var_store_data

    data
  end

  let(:hvar) { Fontisan::Tables::Hvar.read(hvar_data) }
  let(:mvar) { Fontisan::Tables::Mvar.read(mvar_data) }
  let(:processor) { described_class.new(hvar: hvar, mvar: mvar) }

  describe "#initialize" do
    it "creates processor with HVAR table" do
      expect(processor).to be_a(described_class)
    end

    it "loads configuration" do
      expect(processor.config).to be_a(Hash)
    end

    it "can be created with no tables" do
      empty_processor = described_class.new
      expect(empty_processor).to be_a(described_class)
    end
  end

  describe "#has_hvar?" do
    it "returns true when HVAR is present" do
      expect(processor.has_hvar?).to be true
    end

    it "returns false when HVAR is nil" do
      no_hvar = described_class.new(mvar: mvar)
      expect(no_hvar.has_hvar?).to be false
    end
  end

  describe "#has_mvar?" do
    it "returns true when MVAR is present" do
      expect(processor.has_mvar?).to be true
    end

    it "returns false when MVAR is nil" do
      no_mvar = described_class.new(hvar: hvar)
      expect(no_mvar.has_mvar?).to be false
    end
  end

  describe "#advance_width_delta" do
    let(:region_scalars) { [1.0] }

    it "returns delta for glyph with variation" do
      delta = processor.advance_width_delta(0, region_scalars)
      expect(delta).to eq(10)
    end

    it "returns different delta for different glyph" do
      delta = processor.advance_width_delta(1, region_scalars)
      expect(delta).to eq(20)
    end

    it "handles negative deltas" do
      delta = processor.advance_width_delta(2, region_scalars)
      expect(delta).to eq(-5)
    end

    it "scales delta by region scalar" do
      delta = processor.advance_width_delta(0, [0.5])
      # 10 * 0.5 = 5
      expect(delta).to eq(5)
    end

    it "returns 0 when HVAR is nil" do
      no_hvar = described_class.new(mvar: mvar)
      delta = no_hvar.advance_width_delta(0, region_scalars)
      expect(delta).to eq(0)
    end
  end

  describe "#apply_deltas" do
    let(:region_scalars) { [1.0] }

    it "returns horizontal metrics when HVAR present" do
      result = processor.apply_deltas(0, region_scalars)
      expect(result).to have_key(:horizontal)
      expect(result[:horizontal]).to have_key(:advance_width)
    end

    it "includes advance width delta" do
      result = processor.apply_deltas(0, region_scalars)
      expect(result[:horizontal][:advance_width]).to eq(10)
    end

    it "returns empty hash when no tables present" do
      empty_processor = described_class.new
      result = empty_processor.apply_deltas(0, region_scalars)
      expect(result).to eq({})
    end
  end

  describe "#apply_font_metrics" do
    let(:region_scalars) { [1.0] }

    it "returns font-level metrics when MVAR present" do
      result = processor.apply_font_metrics(region_scalars)
      expect(result).to have_key("hasc")
    end

    it "returns scaled delta for metric" do
      result = processor.apply_font_metrics(region_scalars)
      # hasc uses outer=0, inner=0, which is glyph 0 delta = 10
      expect(result["hasc"]).to eq(10)
    end

    it "scales metrics by region scalar" do
      result = processor.apply_font_metrics([0.5])
      expect(result["hasc"]).to eq(5)
    end

    it "returns empty hash when MVAR is nil" do
      no_mvar = described_class.new(hvar: hvar)
      result = no_mvar.apply_font_metrics(region_scalars)
      expect(result).to eq({})
    end
  end

  describe "rounding modes" do
    let(:region_scalars) { [0.6] }

    it "rounds by default" do
      # 10 * 0.6 = 6.0, rounds to 6
      delta = processor.advance_width_delta(0, region_scalars)
      expect(delta).to eq(6)
    end

    it "uses floor when configured" do
      config = { delta_application: { rounding_mode: "floor" } }
      floor_processor = described_class.new(hvar: hvar, config: config)
      # 20 * 0.55 = 11.0, floor to 11
      delta = floor_processor.advance_width_delta(1, [0.55])
      expect(delta).to eq(11)
    end

    it "uses ceil when configured" do
      config = { delta_application: { rounding_mode: "ceil" } }
      ceil_processor = described_class.new(hvar: hvar, config: config)
      # 10 * 0.51 = 5.1, ceil to 6
      delta = ceil_processor.advance_width_delta(0, [0.51])
      expect(delta).to eq(6)
    end
  end

  describe "edge cases" do
    it "handles zero region scalars" do
      delta = processor.advance_width_delta(0, [0.0])
      expect(delta).to eq(0)
    end

    it "handles multiple region scalars" do
      # Only one region in our test data, extra scalars should be ignored
      delta = processor.advance_width_delta(0, [1.0, 0.5])
      expect(delta).to eq(10)
    end

    it "handles invalid glyph ID" do
      delta = processor.advance_width_delta(999, [1.0])
      expect(delta).to eq(0)
    end

    it "handles empty region scalars" do
      delta = processor.advance_width_delta(0, [])
      expect(delta).to eq(0)
    end
  end
end
