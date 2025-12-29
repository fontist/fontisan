# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/optimizer"

RSpec.describe Fontisan::Variation::Optimizer do
  let(:mock_cff2) do
    double("CFF2",
           glyph_count: 3,
           variation_store: mock_variation_store,
           charstring: nil,
           set_charstring: nil,
           local_subr_index: nil,
           "local_subr_index=": nil)
  end

  let(:mock_variation_store) do
    double("VariationStore",
           region_list: mock_regions,
           "region_list=": nil,
           item_variation_data: [])
  end

  let(:mock_regions) do
    [
      mock_region(0.0, 1.0, 1.0),
      mock_region(0.0, 0.5, 1.0),
      mock_region(0.0, 1.0, 1.0), # Duplicate of first
    ]
  end

  def mock_region(start_coord, peak_coord, end_coord)
    double("Region",
           axis_count: 1,
           region_axes: [
             double("RegionAxis",
                    start_coord: start_coord,
                    peak_coord: peak_coord,
                    end_coord: end_coord),
           ])
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

      # Should group the two identical blend1 patterns
      expect(patterns.length).to eq(2)
    end
  end

  describe "#extract_blend_subroutines" do
    let(:optimizer) { described_class.new(mock_cff2) }

    let(:patterns) do
      [
        { sequence: [:blend1], frequency: 3, savings: 100 },
        { sequence: [:blend2], frequency: 2, savings: 50 },
        { sequence: [:blend3], frequency: 1, savings: 20 }, # Should be filtered
      ]
    end

    it "filters patterns by frequency" do
      optimizer.extract_blend_subroutines(patterns)

      expect(optimizer.stats[:subroutines_created]).to be >= 0
    end

    it "respects max_subrs limit" do
      optimizer = described_class.new(mock_cff2, max_subrs: 1)
      optimizer.extract_blend_subroutines(patterns)

      expect(optimizer.stats[:subroutines_created]).to be <= 1
    end
  end

  describe "#deduplicate_regions" do
    let(:optimizer) { described_class.new(mock_cff2) }

    before do
      allow(optimizer).to receive(:update_region_references)
    end

    it "merges duplicate regions" do
      optimizer.deduplicate_regions

      expect(optimizer.stats[:regions_deduplicated]).to eq(1)
    end

    it "updates variation store with unique regions" do
      optimizer.deduplicate_regions

      expect(mock_variation_store).to have_received(:region_list=)
    end

    it "does nothing if no variation store" do
      allow(mock_cff2).to receive(:variation_store).and_return(nil)

      expect { optimizer.deduplicate_regions }.not_to raise_error
    end
  end

  describe "#regions_match?" do
    let(:optimizer) { described_class.new(mock_cff2) }

    it "returns true for identical regions" do
      region1 = mock_region(0.0, 1.0, 1.0)
      region2 = mock_region(0.0, 1.0, 1.0)

      expect(optimizer.send(:regions_match?, region1, region2)).to be true
    end

    it "returns true for regions within threshold" do
      region1 = mock_region(0.0, 1.0, 1.0)
      region2 = mock_region(0.0, 1.0001, 1.0)

      expect(optimizer.send(:regions_match?, region1, region2)).to be true
    end

    it "returns false for different regions" do
      region1 = mock_region(0.0, 1.0, 1.0)
      region2 = mock_region(0.0, 0.5, 1.0)

      expect(optimizer.send(:regions_match?, region1, region2)).to be false
    end

    it "returns false for regions with different axis counts" do
      region1 = mock_region(0.0, 1.0, 1.0)
      region2 = double("Region", axis_count: 2)

      expect(optimizer.send(:regions_match?, region1, region2)).to be false
    end
  end

  describe "#coords_similar?" do
    let(:optimizer) { described_class.new(mock_cff2) }

    it "returns true for identical coordinates" do
      expect(optimizer.send(:coords_similar?, 1.0, 1.0)).to be true
    end

    it "returns true for coordinates within threshold" do
      expect(optimizer.send(:coords_similar?, 1.0, 1.0005)).to be true
    end

    it "returns false for coordinates outside threshold" do
      expect(optimizer.send(:coords_similar?, 1.0, 1.5)).to be false
    end
  end

  describe "#optimize_item_variation_store" do
    let(:optimizer) { described_class.new(mock_cff2) }

    before do
      allow(optimizer).to receive(:compact_variation_data)
      allow(optimizer).to receive(:optimize_delta_encoding)
    end

    it "compacts and optimizes variation store" do
      optimizer.send(:optimize_item_variation_store)

      expect(optimizer).to have_received(:compact_variation_data)
      expect(optimizer).to have_received(:optimize_delta_encoding)
    end

    it "does nothing if no variation store" do
      allow(mock_cff2).to receive(:variation_store).and_return(nil)

      expect do
        optimizer.send(:optimize_item_variation_store)
      end.not_to raise_error
    end
  end

  describe "#statistics" do
    let(:optimizer) { described_class.new(mock_cff2) }

    it "returns statistics hash" do
      stats = optimizer.statistics

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:original_size)
      expect(stats).to have_key(:optimized_size)
      expect(stats).to have_key(:blend_patterns_found)
      expect(stats).to have_key(:subroutines_created)
      expect(stats).to have_key(:regions_deduplicated)
    end
  end

  describe "integration" do
    context "with real blend patterns" do
      let(:optimizer) { described_class.new(mock_cff2) }

      it "optimizes CFF2 table successfully" do
        allow(optimizer).to receive(:estimate_table_size).and_return(1000, 750)
        allow(optimizer).to receive(:analyze_blend_patterns).and_return([
                                                                          {
                                                                            sequence: [:blend], frequency: 5, savings: 100
                                                                          },
                                                                        ])

        result = optimizer.optimize

        expect(result).to eq(mock_cff2)
        expect(optimizer.stats[:savings_percent]).to eq(25.0)
      end
    end
  end
end
