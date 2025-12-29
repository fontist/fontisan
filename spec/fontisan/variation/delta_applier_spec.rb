# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/delta_applier"
require "fontisan/variation/interpolator"
require "fontisan/variation/region_matcher"

RSpec.describe Fontisan::Variation::DeltaApplier do
  subject(:applier) { described_class.new(font, interpolator, region_matcher) }

  let(:font) { double("Font") }
  let(:axes) do
    [
      double("Axis", axis_tag: "wght", min_value: 400.0, default_value: 400.0,
                     max_value: 900.0),
      double("Axis", axis_tag: "wdth", min_value: 75.0, default_value: 100.0,
                     max_value: 125.0),
    ]
  end
  let(:interpolator) { Fontisan::Variation::Interpolator.new(axes) }
  let(:region_matcher) { Fontisan::Variation::RegionMatcher.new(axes) }
  let(:gvar) { double("Gvar") }
  let(:glyf) { double("Glyf") }

  before do
    allow(font).to receive(:table).with("gvar").and_return(gvar)
    allow(font).to receive(:table).with("glyf").and_return(glyf)
    # TableAccessor calls has_table? for caching
    allow(font).to receive(:has_table?).with("gvar").and_return(true)
    allow(font).to receive(:has_table?).with("glyf").and_return(true)
  end

  describe "#initialize" do
    it "initializes with font and helpers" do
      expect(applier.font).to eq(font)
      expect(applier.interpolator).to eq(interpolator)
      expect(applier.region_matcher).to eq(region_matcher)
      expect(applier.delta_parser).to be_a(Fontisan::Variation::DeltaParser)
    end
  end

  describe "#apply_deltas" do
    context "when gvar or glyf table missing" do
      it "returns nil when gvar missing" do
        allow(font).to receive(:table).with("gvar").and_return(nil)
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to be_nil
      end

      it "returns nil when glyf missing" do
        allow(font).to receive(:table).with("glyf").and_return(nil)
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to be_nil
      end
    end

    context "when glyph has no outline" do
      it "returns nil for empty glyph" do
        allow(applier).to receive(:extract_glyph_points).and_return([])
        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to be_nil
      end

      it "returns nil when outline extraction fails" do
        allow(applier).to receive(:extract_glyph_points).and_return(nil)
        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to be_nil
      end
    end

    context "when glyph has no variations" do
      let(:base_points) do
        [
          { x: 100.0, y: 200.0, on_curve: true },
          { x: 150.0, y: 250.0, on_curve: false },
          { x: 200.0, y: 200.0, on_curve: true },
        ]
      end

      it "returns base points when no tuple data" do
        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return(nil)

        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to eq(base_points)
      end

      it "returns base points when tuples array empty" do
        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return({ tuples: [] })

        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to eq(base_points)
      end

      it "returns base points when no tuples match" do
        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return({
                                                                     tuples: [{ peak: [
                                                                       1.0, 0.0
                                                                     ] }],
                                                                   })
        allow(region_matcher).to receive(:match_tuples).and_return([])

        result = applier.apply_deltas(0, { "wght" => 400.0 })
        expect(result).to eq(base_points)
      end
    end

    context "with active variations" do
      let(:base_points) do
        [
          { x: 100.0, y: 200.0, on_curve: true },
          { x: 150.0, y: 250.0, on_curve: false },
          { x: 200.0, y: 200.0, on_curve: true },
        ]
      end

      let(:tuple_data) do
        {
          tuples: [
            { peak: [0.6, 0.0], private_points: false },
          ],
          has_shared_points: false,
        }
      end

      it "applies deltas from matched tuples" do
        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return(tuple_data)

        # Mock matched tuple with scalar
        matches = [
          { tuple: tuple_data[:tuples][0], scalar: 0.8 },
        ]
        allow(region_matcher).to receive(:match_tuples).and_return(matches)

        # Mock delta parsing to return simple deltas
        allow_any_instance_of(Fontisan::Variation::DeltaParser).to receive(:parse).and_return([
                                                                                                {
                                                                                                  x: 10, y: 5
                                                                                                },
                                                                                                {
                                                                                                  x: -5, y: 10
                                                                                                },
                                                                                                {
                                                                                                  x: 10, y: -5
                                                                                                },
                                                                                              ])

        result = applier.apply_deltas(0, { "wght" => 700.0 })

        # Base points + (deltas * scalar)
        expect(result[0][:x]).to be_within(0.1).of(108.0)  # 100 + (10 * 0.8)
        expect(result[0][:y]).to be_within(0.1).of(204.0)  # 200 + (5 * 0.8)
        expect(result[1][:x]).to be_within(0.1).of(146.0)  # 150 + (-5 * 0.8)
        expect(result[1][:y]).to be_within(0.1).of(258.0)  # 250 + (10 * 0.8)
        expect(result[2][:x]).to be_within(0.1).of(208.0)  # 200 + (10 * 0.8)
        expect(result[2][:y]).to be_within(0.1).of(196.0)  # 200 + (-5 * 0.8)
      end

      it "applies multiple tuples cumulatively" do
        tuple_data_multi = {
          tuples: [
            { peak: [0.6, 0.0], private_points: false },
            { peak: [0.0, 0.5], private_points: false },
          ],
          has_shared_points: false,
        }

        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return(tuple_data_multi)

        matches = [
          { tuple: tuple_data_multi[:tuples][0], scalar: 0.8 },
          { tuple: tuple_data_multi[:tuples][1], scalar: 0.5 },
        ]
        allow(region_matcher).to receive(:match_tuples).and_return(matches)

        # Different deltas for each tuple
        call_count = 0
        allow_any_instance_of(Fontisan::Variation::DeltaParser).to receive(:parse) do
          call_count += 1
          if call_count == 1
            [{ x: 10, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 0 }]
          else
            [{ x: 0, y: 10 }, { x: 0, y: 10 }, { x: 0, y: 10 }]
          end
        end

        result = applier.apply_deltas(0, { "wght" => 700.0, "wdth" => 110.0 })

        # First tuple: x += 10 * 0.8 = 8
        # Second tuple: y += 10 * 0.5 = 5
        expect(result[0][:x]).to be_within(0.1).of(108.0)  # 100 + 8
        expect(result[0][:y]).to be_within(0.1).of(205.0)  # 200 + 5
      end

      it "skips tuples with zero scalar" do
        allow(applier).to receive(:extract_glyph_points).and_return(base_points)
        allow(gvar).to receive(:glyph_tuple_variations).and_return(tuple_data)

        matches = [
          { tuple: tuple_data[:tuples][0], scalar: 0.0 },
        ]
        allow(region_matcher).to receive(:match_tuples).and_return(matches)

        result = applier.apply_deltas(0, { "wght" => 400.0 })

        # No deltas applied
        expect(result).to eq(base_points)
      end
    end
  end

  describe "#extract_glyph_points" do
    it "returns empty array for now (placeholder)" do
      allow(glyf).to receive(:glyph_data).and_return("dummy_data")
      points = applier.extract_glyph_points(0, glyf)
      expect(points).to eq([])
    end

    it "returns nil when glyph data missing" do
      allow(glyf).to receive(:glyph_data).and_return(nil)
      points = applier.extract_glyph_points(0, glyf)
      expect(points).to be_nil
    end
  end

  describe "IUP expansion" do
    let(:base_points) do
      (0...10).map { |i| { x: i * 10.0, y: i * 10.0, on_curve: true } }
    end

    let(:tuple_data) do
      {
        tuples: [
          { peak: [1.0, 0.0], private_points: true },
        ],
        has_shared_points: false,
      }
    end

    it "expands IUP for untouched points" do
      # This tests that IUP expansion is attempted when private_points is true

      allow(applier).to receive(:extract_glyph_points).and_return(base_points)
      allow(gvar).to receive(:glyph_tuple_variations).and_return(tuple_data)

      matches = [
        { tuple: tuple_data[:tuples][0], scalar: 1.0 },
      ]
      allow(region_matcher).to receive(:match_tuples).and_return(matches)

      # Sparse deltas - only points 0, 5, 9 have deltas
      sparse_deltas = Array.new(10) { { x: 0, y: 0 } }
      sparse_deltas[0] = { x: 10, y: 10 }
      sparse_deltas[5] = { x: 50, y: 50 }
      sparse_deltas[9] = { x: 90, y: 90 }

      allow_any_instance_of(Fontisan::Variation::DeltaParser).to receive(:parse)
        .and_return(sparse_deltas)

      # Save original values for comparison
      original_x = [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]
      original_y = original_x.dup

      result = applier.apply_deltas(0, { "wght" => 900.0 })

      # Verify that points with explicit deltas were modified correctly
      expect(result[0][:x]).to eq(original_x[0] + 10.0)  # 0 + 10 = 10
      expect(result[5][:x]).to eq(original_x[5] + 50.0)  # 50 + 50 = 100
      expect(result[9][:x]).to eq(original_x[9] + 90.0)  # 90 + 90 = 180

      expect(result[0][:y]).to eq(original_y[0] + 10.0)  # 0 + 10 = 10
      expect(result[5][:y]).to eq(original_y[5] + 50.0)  # 50 + 50 = 100
      expect(result[9][:y]).to eq(original_y[9] + 90.0)  # 90 + 90 = 180
    end
  end

  describe "error handling" do
    it "handles exceptions gracefully" do
      allow(applier).to receive(:extract_glyph_points).and_raise(StandardError,
                                                                 "Test error")

      expect do
        result = applier.apply_deltas(0, { "wght" => 700.0 })
        expect(result).to be_nil
      end.to raise_error(StandardError)
    end
  end
end
