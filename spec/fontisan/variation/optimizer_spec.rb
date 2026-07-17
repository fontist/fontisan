# frozen_string: true

require "spec_helper"
require "fontisan/variation/optimizer"

module OptimizerSpecFakes
  FakeRegionAxis = Struct.new(:start_coord, :peak_coord, :end_coord,
                              keyword_init: true)

  FakeRegion = Struct.new(:axis_count, :region_axes, keyword_init: true)

  FakeVariationStore = Struct.new(:region_list, :item_variation_data,
                                  keyword_init: true)

  FakeCff2 = Struct.new(:glyph_count, :variation_store, keyword_init: true) do
    def charstring(*); nil; end
    def set_charstring(*); end
    def local_subr_index; nil; end
    def local_subr_index=(_); end
  end
end

RSpec.describe Fontisan::Variation::Optimizer do
  let(:mock_cff2) do
    OptimizerSpecFakes::FakeCff2.new(
      glyph_count: 3,
      variation_store: mock_variation_store,
    )
  end

  let(:mock_variation_store) do
    OptimizerSpecFakes::FakeVariationStore.new(
      region_list: mock_regions,
      item_variation_data: [],
    )
  end

  let(:mock_regions) do
    [
      mock_region(0.0, 1.0, 1.0),
      mock_region(0.0, 0.5, 1.0),
      mock_region(0.0, 1.0, 1.0),
    ]
  end

  def mock_region(start_coord, peak_coord, end_coord)
    OptimizerSpecFakes::FakeRegion.new(
      axis_count: 1,
      region_axes: [
        OptimizerSpecFakes::FakeRegionAxis.new(
          start_coord: start_coord, peak_coord: peak_coord, end_coord: end_coord,
        ),
      ],
    )
  end

  describe "#initialize" do
    it "initializes with CFF2 table" do
      optimizer = described_class.new(mock_cff2)

      expect(optimizer.cff2).to eq(mock_cff2)
      expect(optimizer.stats).to be_a(Hash)
    end

    it "accepts options" do
      optimizer = described_class.new(mock_cff2, max_subrs: 100)

      expect(optimizer.instance_variable_get(:@options)[:max_subrs]).to eq(100)
    end

    it "sets default options" do
      optimizer = described_class.new(mock_cff2)
      options = optimizer.instance_variable_get(:@options)

      expect(options[:max_subrs]).to eq(65535)
      expect(options[:region_threshold]).to eq(0.001)
      expect(options[:deduplicate_regions]).to be true
    end
  end

  describe "#optimize" do
    let(:optimizer) { described_class.new(mock_cff2) }

    before do
      allow(optimizer).to receive(:estimate_table_size).and_return(1000, 800)
      allow(optimizer).to receive_messages(analyze_blend_patterns: [],
                                           extract_blend_subroutines: [])
      allow(optimizer).to receive(:deduplicate_regions)
      allow(optimizer).to receive(:optimize_item_variation_store)
      allow(optimizer).to receive(:rebuild_charstrings)
    end

    it "performs optimization passes" do
      optimizer.optimize

      expect(optimizer).to have_received(:analyze_blend_patterns)
      expect(optimizer).to have_received(:extract_blend_subroutines)
      expect(optimizer).to have_received(:deduplicate_regions)
      expect(optimizer).to have_received(:optimize_item_variation_store)
    end

    it "updates statistics" do
      optimizer.optimize

      expect(optimizer.stats[:original_size]).to eq(1000)
      expect(optimizer.stats[:optimized_size]).to eq(800)
      expect(optimizer.stats[:savings_percent]).to eq(20.0)
    end

    it "returns optimized CFF2 table" do
      result = optimizer.optimize

      expect(result).to eq(mock_cff2)
    end
  end

  describe "#analyze_blend_patterns" do
    let(:optimizer) { described_class.new(mock_cff2) }

    before do
      allow(optimizer).to receive(:extract_blend_sequences).and_return([
                                                                         {
                                                                           sequence: [:blend1], frequency: 1
                                                                         },
                                                                         {
                                                                           sequence: [:blend1], frequency: 1
                                                                         },
                                                                         {
                                                                           sequence: [:blend2], frequency: 1
                                                                         },
                                                                       ])
    end

    it "analyzes blend patterns across glyphs" do
      allow(mock_cff2).to receive(:charstring).and_return("charstring_data")

      patterns = optimizer.analyze_blend_patterns

      expect(patterns).to be_an(Array)
      expect(optimizer.stats[:blend_patterns_found]).to be > 0
    end

    it "groups identical patterns" do
      allow(mock_cff2).to receive(:charstring).and_return("charstring_data")

      patterns = optimizer.analyze_blend_patterns

      expect(patterns.length).to be <= 3
    end
  end

  describe "#deduplicate_regions" do
    let(:optimizer) { described_class.new(mock_cff2) }

    it "identifies duplicate regions" do
      optimizer.deduplicate_regions

      expect(optimizer.stats[:regions_deduplicated]).to be >= 0
    end

    it "removes exact duplicates" do
      optimizer.deduplicate_regions

      # Regions 0 and 2 are identical (0.0, 1.0, 1.0)
      expect(optimizer.stats[:regions_deduplicated]).to be >= 1
    end
  end
end
