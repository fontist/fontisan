# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/metrics_adjuster"
require "fontisan/variation/interpolator"

RSpec.describe Fontisan::Variation::MetricsAdjuster do
  let(:font) { double("Font") }
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
        allow(font).to receive(:has_table?).with("HVAR").and_return(false)

        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end

    context "when hmtx table is missing" do
      it "returns false" do
        allow(font).to receive(:has_table?).with("HVAR").and_return(true)
        allow(font).to receive(:has_table?).with("hmtx").and_return(false)

        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end

    context "when HVAR has no item variation store" do
      it "returns false" do
        hvar = double("HVAR", item_variation_store: nil)

        allow(font).to receive(:has_table?).with("HVAR").and_return(true)
        allow(font).to receive(:has_table?).with("hmtx").and_return(true)
        allow(font).to receive(:table).with("HVAR").and_return(hvar)

        result = adjuster.apply_hvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end

    context "when tables are valid" do
      let(:store) { double("ItemVariationStore") }
      let(:region_list) { double("RegionList", regions: []) }
      let(:hvar) { double("HVAR", item_variation_store: store) }

      before do
        allow(font).to receive(:has_table?).with("HVAR").and_return(true)
        allow(font).to receive(:has_table?).with("hmtx").and_return(true)
        allow(font).to receive(:table).with("HVAR").and_return(hvar)
        allow(store).to receive(:variation_region_list).and_return(region_list)
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
        allow(font).to receive(:has_table?).with("VVAR").and_return(false)

        result = adjuster.apply_vvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end

    context "when vmtx table is missing" do
      it "returns false" do
        allow(font).to receive(:has_table?).with("VVAR").and_return(true)
        allow(font).to receive(:has_table?).with("vmtx").and_return(false)

        result = adjuster.apply_vvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end
  end

  describe "#apply_mvar_deltas" do
    context "when MVAR table is missing" do
      it "returns false" do
        allow(font).to receive(:has_table?).with("MVAR").and_return(false)

        result = adjuster.apply_mvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end

    context "when MVAR has no item variation store" do
      it "returns false" do
        mvar = double("MVAR", item_variation_store: nil)

        allow(font).to receive(:has_table?).with("MVAR").and_return(true)
        allow(font).to receive(:table).with("MVAR").and_return(mvar)

        result = adjuster.apply_mvar_deltas({ "wght" => 700.0 })

        expect(result).to be false
      end
    end
  end

  describe "private methods" do
    describe "#extract_regions_from_store" do
      let(:axis) do
        double("Axis",
               axis_tag: "wght",
               min_value: 400.0,
               default_value: 400.0,
               max_value: 900.0)
      end

      let(:interpolator) { Fontisan::Variation::Interpolator.new([axis]) }
      let(:adjuster) { described_class.new(font, interpolator) }

      it "extracts regions from variation region list" do
        # Create mock region coordinates
        coords = double("RegionAxisCoordinates",
                        start: -0.5,
                        peak: 0.0,
                        end_value: 0.5)

        region_list = double("RegionList", regions: [[coords]])
        store = double("ItemVariationStore", variation_region_list: region_list)

        regions = adjuster.send(:extract_regions_from_store, store)

        expect(regions).to be_an(Array)
        expect(regions.length).to eq(1)
        expect(regions[0]).to have_key("wght")
        expect(regions[0]["wght"]).to include(
          start: -0.5,
          peak: 0.0,
          end: 0.5
        )
      end

      it "returns empty array when no region list" do
        store = double("ItemVariationStore", variation_region_list: nil)

        regions = adjuster.send(:extract_regions_from_store, store)

        expect(regions).to eq([])
      end
    end

    describe "#get_base_metric_value" do
      it "returns ascender for hasc tag" do
        hhea = double("hhea", ascender: 800)
        allow(font).to receive(:has_table?).with("hhea").and_return(true)
        allow(font).to receive(:table).with("hhea").and_return(hhea)

        value = adjuster.send(:get_base_metric_value, "hasc")

        expect(value).to eq(800)
      end

      it "returns descender for hdsc tag" do
        hhea = double("hhea", descender: -200)
        allow(font).to receive(:has_table?).with("hhea").and_return(true)
        allow(font).to receive(:table).with("hhea").and_return(hhea)

        value = adjuster.send(:get_base_metric_value, "hdsc")

        expect(value).to eq(-200)
      end

      it "returns line_gap for hlgp tag" do
        hhea = double("hhea", line_gap: 100)
        allow(font).to receive(:has_table?).with("hhea").and_return(true)
        allow(font).to receive(:table).with("hhea").and_return(hhea)

        value = adjuster.send(:get_base_metric_value, "hlgp")

        expect(value).to eq(100)
      end

      it "returns nil for unknown tag" do
        value = adjuster.send(:get_base_metric_value, "unknown")

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

        # Mock hhea update
        allow(font).to receive(:has_table?).with("hhea").and_return(true)
        hhea = double("hhea")
        allow(hhea).to receive(:respond_to?).with(:number_of_h_metrics=).and_return(true)
        allow(hhea).to receive(:number_of_h_metrics=)
        allow(font).to receive(:table).with("hhea").and_return(hhea)

        data = adjuster.send(:build_hmtx_data, metrics)

        expect(data).to be_a(String)
        expect(data.encoding).to eq(Encoding::BINARY)
        # Optimizer finds last advance width (700) appears at index 1 and 2
        # So number_of_h_metrics = 2 (not 3)
        # 2 LongHorMetric (4 bytes each) = 8 bytes
        expect(data.bytesize).to eq(8)
      end

      it "returns nil for empty metrics" do
        data = adjuster.send(:build_hmtx_data, [])

        expect(data).to be_nil
      end
    end
  end
end
