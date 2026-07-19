# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/metrics_adjuster"
require "fontisan/variation/interpolator"

module MetricsAdjusterSpecFakes
  FakeHhea = Struct.new(:ascender, :descender, :line_gap, :number_of_h_metrics,
                        keyword_init: true)
  FakeCoord = Struct.new(:start, :peak, :end_value, keyword_init: true)
end

RSpec.describe Fontisan::Variation::MetricsAdjuster do
  let(:font) { Fontisan::SpecHelpers::FakeFont.new({}) }
  let(:axes) { [] }
  let(:interpolator) { Fontisan::Variation::Interpolator.new(axes) }
  let(:adjuster) { described_class.new(font, interpolator) }

  describe "#initialize" do
    it "stores font and interpolator" do
      expect(adjuster.font).to eq(font)
      expect(adjuster.interpolator).to eq(interpolator)
    end
  end

  describe "#apply_hvar_deltas" do
    context "when HVAR table is missing" do
      it "returns false" do
        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end

    context "when hmtx table is missing" do
      it "returns false" do
        font.tables_hash["HVAR"] = Fontisan::SpecHelpers::FakeHvar.new(item_variation_store: nil)

        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end

    context "when HVAR has no item variation store" do
      it "returns false" do
        font.tables_hash["HVAR"] = Fontisan::SpecHelpers::FakeHvar.new(item_variation_store: nil)
        font.tables_hash["hmtx"] = "hmtx_data"

        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end

    context "when tables are valid" do
      let(:region_list) { Fontisan::SpecHelpers::FakeRegionList.new(regions: []) }
      let(:store) do
        Fontisan::SpecHelpers::FakeStore.new(variation_region_list: region_list,
                                             item_variation_data_entries: [])
      end
      let(:hvar) { Fontisan::SpecHelpers::FakeHvar.new(item_variation_store: store) }

      before do
        font.tables_hash["HVAR"] = hvar
        font.tables_hash["hmtx"] = "hmtx_data"
      end

      it "returns false when no regions" do
        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end
  end

  describe "#apply_vvar_deltas" do
    context "when VVAR table is missing" do
      it "returns false" do
        result = adjuster.apply_vvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end

    context "when vmtx table is missing" do
      it "returns false" do
        font.tables_hash["VVAR"] = Fontisan::SpecHelpers::FakeHvar.new(item_variation_store: nil)

        result = adjuster.apply_vvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end
  end

  describe "#apply_mvar_deltas" do
    context "when MVAR table is missing" do
      it "returns false" do
        result = adjuster.apply_mvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end

    context "when MVAR has no item variation store" do
      it "returns false" do
        font.tables_hash["MVAR"] = Fontisan::SpecHelpers::FakeMvar.new(item_variation_store: nil)

        result = adjuster.apply_mvar_deltas({ "wght" => 700.0 })
        expect(result).to be false
      end
    end
  end

  describe "private methods" do
    describe "#extract_regions_from_store" do
      let(:axis) do
        Fontisan::SpecHelpers::FakeAxis.new(axis_tag: "wght", min_value: 400.0, default_value: 400.0, max_value: 900.0)
      end

      let(:interpolator) { Fontisan::Variation::Interpolator.new([axis]) }
      let(:adjuster) { described_class.new(font, interpolator) }

      it "extracts regions from variation region list" do
        coords = MetricsAdjusterSpecFakes::FakeCoord.new(start: -0.5, peak: 0.0, end_value: 0.5)
        region_list = Fontisan::SpecHelpers::FakeRegionList.new(regions: [[coords]])
        store = Fontisan::SpecHelpers::FakeStore.new(variation_region_list: region_list)

        regions = adjuster.extract_regions_from_store(store)

        expect(regions).to be_an(Array)
        expect(regions.length).to eq(1)
        expect(regions[0]).to have_key("wght")
        expect(regions[0]["wght"]).to include(
          start: -0.5,
          peak: 0.0,
          end: 0.5,
        )
      end

      it "returns empty array when no region list" do
        store = Fontisan::SpecHelpers::FakeStore.new(variation_region_list: nil)

        regions = adjuster.extract_regions_from_store(store)

        expect(regions).to eq([])
      end
    end

    describe "#get_base_metric_value" do
      it "returns ascender for hasc tag" do
        font.tables_hash["hhea"] = MetricsAdjusterSpecFakes::FakeHhea.new(ascender: 800)

        value = adjuster.get_base_metric_value("hasc")
        expect(value).to eq(800)
      end

      it "returns descender for hdsc tag" do
        font.tables_hash["hhea"] = MetricsAdjusterSpecFakes::FakeHhea.new(descender: -200)

        value = adjuster.get_base_metric_value("hdsc")
        expect(value).to eq(-200)
      end

      it "returns line_gap for hlgp tag" do
        font.tables_hash["hhea"] = MetricsAdjusterSpecFakes::FakeHhea.new(line_gap: 100)

        value = adjuster.get_base_metric_value("hlgp")
        expect(value).to eq(100)
      end

      it "returns nil for unknown tag" do
        value = adjuster.get_base_metric_value("unknown")
        expect(value).to be_nil
      end
    end

    describe "#build_hmtx_data" do
      it "builds binary data from metrics" do
        metrics = [
          { advance_width: 600, lsb: 50 },
          { advance_width: 700, lsb: 60 },
          { advance_width: 700, lsb: 70 },
        ]

        font.tables_hash["hhea"] = MetricsAdjusterSpecFakes::FakeHhea.new

        data = adjuster.build_hmtx_data(metrics)

        expect(data).to be_a(String)
        expect(data.encoding).to eq(Encoding::BINARY)
        expect(data.bytesize).to eq(8)
      end

      it "returns nil for empty metrics" do
        data = adjuster.build_hmtx_data([])

        expect(data).to be_nil
      end
    end
  end
end
