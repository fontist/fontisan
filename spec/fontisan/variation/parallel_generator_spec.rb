# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "fontisan/variation/parallel_generator"

RSpec.describe Fontisan::Variation::ParallelGenerator do
  let(:font) { instance_double("TrueTypeFont") }
  let(:fvar) { instance_double("Fvar", axes: axes) }
  let(:axes) do
    [
      instance_double("VariationAxisRecord", axis_tag: "wght", min_value: 100.0, max_value: 900.0, default_value: 400.0),
      instance_double("VariationAxisRecord", axis_tag: "wdth", min_value: 75.0, max_value: 125.0, default_value: 100.0)
    ]
  end

  before do
    allow(font).to receive(:table).with("fvar").and_return(fvar)
    allow(font).to receive(:table_data).and_return({})
    # Generic mock first, then specific override for fvar (order matters in RSpec)
    allow(font).to receive(:has_table?).and_return(false)
    allow(font).to receive(:has_table?).with("fvar").and_return(true)
  end

  describe "#initialize" do
    it "initializes with font" do
      generator = described_class.new(font)
      expect(generator.font).to eq(font)
    end

    it "uses default thread count of max(4, processor_count)" do
      generator = described_class.new(font)
      expect(generator.thread_count).to be >= 4
    end

    it "accepts custom thread count" do
      generator = described_class.new(font, threads: 8)
      expect(generator.thread_count).to eq(8)
    end

    it "creates default cache if not provided" do
      generator = described_class.new(font)
      expect(generator.cache).to be_a(Fontisan::Variation::ThreadSafeCache)
    end

    it "accepts custom cache" do
      custom_cache = Fontisan::Variation::ThreadSafeCache.new
      generator = described_class.new(font, cache: custom_cache)
      expect(generator.cache).to eq(custom_cache)
    end
  end

  describe "#generate_batch" do
    let(:generator) { described_class.new(font, threads: 2) }
    let(:coordinates_list) do
      [
        { "wght" => 300.0 },
        { "wght" => 700.0 },
        { "wght" => 900.0 }
      ]
    end

    it "returns empty array for empty input" do
      result = generator.generate_batch([])
      expect(result).to eq([])
    end

    it "generates multiple instances" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return({ "glyf" => "data" })

      results = generator.generate_batch(coordinates_list)
      expect(results.size).to eq(3)
      expect(results.all? { |r| r[:success] }).to be true
    end

    it "maintains result order" do
      call_order = []
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate) do
          coords = Thread.current[:test_coordinates]
          call_order << coords
          { "glyf" => "data_#{coords['wght']}" }
        end

      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:initialize) do |_self, _font, coords|
          Thread.current[:test_coordinates] = coords
        end

      results = generator.generate_batch(coordinates_list)

      # Results should be in same order as input
      expect(results[0][:coordinates]).to eq({ "wght" => 300.0 })
      expect(results[1][:coordinates]).to eq({ "wght" => 700.0 })
      expect(results[2][:coordinates]).to eq({ "wght" => 900.0 })
    end

    it "reports progress via callback" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return({ "glyf" => "data" })

      progress_calls = []
      generator.generate_batch(coordinates_list) do |current, total|
        progress_calls << [current, total]
      end

      expect(progress_calls.size).to eq(3)
      expect(progress_calls.map(&:last).uniq).to eq([3])
      expect(progress_calls.map(&:first).sort).to eq([1, 2, 3])
    end

    it "handles errors gracefully per instance" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_raise(StandardError, "Test error")

      results = generator.generate_batch(coordinates_list)

      expect(results.size).to eq(3)
      expect(results.all? { |r| !r[:success] }).to be true
      expect(results.all? { |r| r[:error][:message] == "Test error" }).to be true
    end

    it "includes error details in failed results" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_raise(StandardError, "Test error")

      results = generator.generate_batch(coordinates_list)
      error = results.first[:error]

      expect(error[:message]).to eq("Test error")
      expect(error[:class]).to eq("StandardError")
      expect(error[:backtrace]).to be_an(Array)
    end

    it "uses cache for repeated coordinates" do
      cache = Fontisan::Variation::ThreadSafeCache.new
      generator = described_class.new(font, threads: 2, cache: cache)

      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return({ "glyf" => "data" })

      # Generate once
      generator.generate_batch([{ "wght" => 700.0 }])

      # Generate again with same coordinates
      expect_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .not_to receive(:generate)

      results = generator.generate_batch([{ "wght" => 700.0 }])
      expect(results.first[:success]).to be true
    end

    it "returns successful results with tables" do
      expected_tables = { "glyf" => "glyph_data", "hmtx" => "metrics" }
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return(expected_tables)

      results = generator.generate_batch([{ "wght" => 700.0 }])
      result = results.first

      expect(result[:success]).to be true
      expect(result[:tables]).to eq(expected_tables)
      expect(result[:coordinates]).to eq({ "wght" => 700.0 })
      expect(result[:error]).to be_nil
    end
  end

  describe "#generate_with_cache" do
    let(:generator) { described_class.new(font) }
    let(:coordinates) { { "wght" => 700.0 } }

    it "generates instance on cache miss" do
      expected_tables = { "glyf" => "data" }
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return(expected_tables)

      result = generator.generate_with_cache(coordinates)

      expect(result[:success]).to be true
      expect(result[:tables]).to eq(expected_tables)
    end

    it "returns cached instance on cache hit" do
      expected_tables = { "glyf" => "data" }
      call_count = 0

      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate) do
          call_count += 1
          expected_tables
        end

      # First call - should generate
      result1 = generator.generate_with_cache(coordinates)
      # Second call - should use cache
      result2 = generator.generate_with_cache(coordinates)

      expect(result1[:tables]).to eq(expected_tables)
      expect(result2[:tables]).to eq(expected_tables)
      expect(call_count).to eq(1) # Should only generate once
    end

    it "returns error result on exception" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_raise(StandardError, "Generation failed")

      result = generator.generate_with_cache(coordinates)

      expect(result[:success]).to be false
      expect(result[:tables]).to be_nil
      expect(result[:error][:message]).to eq("Generation failed")
    end
  end

  describe "thread safety" do
    let(:generator) { described_class.new(font, threads: 4) }

    it "handles concurrent access safely" do
      coordinates_list = 20.times.map { |i| { "wght" => 100.0 + (i * 40) } }

      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate).and_return({ "glyf" => "data" })

      results = generator.generate_batch(coordinates_list)

      expect(results.size).to eq(20)
      expect(results.all? { |r| r[:success] }).to be true
    end
  end

  describe "performance" do
    let(:sequential_generator) { described_class.new(font, threads: 1) }
    let(:parallel_generator) { described_class.new(font, threads: 4) }
    let(:coordinates_list) { 12.times.map { |i| { "wght" => 100.0 + (i * 60) } } }

    it "performs better than sequential for large batches" do
      allow_any_instance_of(Fontisan::Variation::InstanceGenerator)
        .to receive(:generate) do
          sleep(0.01) # Simulate work
          { "glyf" => "data" }
        end

      sequential_time = Benchmark.realtime do
        sequential_generator.generate_batch(coordinates_list)
      end

      parallel_time = Benchmark.realtime do
        parallel_generator.generate_batch(coordinates_list)
      end

      # Parallel should be faster (with some tolerance for overhead)
      expect(parallel_time).to be < (sequential_time * 0.8)
    end
  end
end
