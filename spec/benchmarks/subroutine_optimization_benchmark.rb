# frozen_string_literal: true

# rubocop:disable Lint/UselessAssignment
# Benchmarks calculate values for timing without using them to prevent JIT compiler optimization

require "spec_helper"
require "benchmark"

# Benchmark script for subroutine optimization performance
#
# This benchmark measures the performance impact of subroutine optimization
# during TTF→OTF conversion, including:
# - Conversion time with and without optimization
# - Optimization overhead
# - Pattern analysis performance
# - Memory usage patterns
#
# Usage:
#   ruby spec/benchmarks/subroutine_optimization_benchmark.rb

RSpec.describe "Subroutine Optimization Performance" do
  let(:ttf_font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:converter) { Fontisan::Converters::OutlineConverter.new }
  let(:font) { Fontisan::FontLoader.load(ttf_font_path) }

  describe "Conversion Performance" do
    it "benchmarks conversion without optimization" do
      times = []
      5.times do |_i|
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: false)
        end
        times << time
      end

      avg = times.sum / times.length
      times.min
      times.max
      Math.sqrt(times.sum { |t| (t - avg)**2 } / times.length)
    end

    it "benchmarks conversion with optimization" do
      times = []
      5.times do |_i|
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: true)
        end
        times << time
      end

      avg = times.sum / times.length
      times.min
      times.max
      Math.sqrt(times.sum { |t| (t - avg)**2 } / times.length)
    end

    it "compares overhead of optimization" do
      # Baseline: without optimization
      baseline_times = []
      3.times do
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: false)
        end
        baseline_times << time
      end
      baseline_avg = baseline_times.sum / baseline_times.length

      # With optimization
      optimized_times = []
      3.times do
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: true)
        end
        optimized_times << time
      end
      optimized_avg = optimized_times.sum / optimized_times.length

      overhead = optimized_avg - baseline_avg
      (overhead / baseline_avg * 100)
    end
  end

  describe "Parameter Impact" do
    it "benchmarks different min_pattern_length values" do
      [5, 10, 15, 20].each do |min_length|
        Benchmark.realtime do
          result = converter.convert(font, {
                                       target_format: :otf,
                                       optimize_subroutines: true,
                                       min_pattern_length: min_length,
                                     })

          result.instance_variable_get(:@subroutine_optimization)
        end
      end
    end

    it "benchmarks different max_subroutines values" do
      [100, 1000, 10_000, 65_535].each do |max_subrs|
        Benchmark.realtime do
          result = converter.convert(font, {
                                       target_format: :otf,
                                       optimize_subroutines: true,
                                       max_subroutines: max_subrs,
                                     })

          result.instance_variable_get(:@subroutine_optimization)
        end
      end
    end
  end

  describe "Memory Usage" do
    it "estimates memory overhead" do
      # Baseline conversion
      GC.start
      before_memory = GC.stat(:heap_allocated_pages)

      converter.convert(font, target_format: :otf, optimize_subroutines: false)

      after_baseline = GC.stat(:heap_allocated_pages)
      after_baseline - before_memory

      # With optimization
      GC.start
      before_memory = GC.stat(:heap_allocated_pages)

      result = converter.convert(font, target_format: :otf,
                                       optimize_subroutines: true)

      after_optimized = GC.stat(:heap_allocated_pages)
      after_optimized - before_memory

      result.instance_variable_get(:@subroutine_optimization)
    end
  end

  describe "Scalability" do
    it "shows performance characteristics summary" do
      # Single run with detailed timing
      start_time = Time.now

      result = converter.convert(font, {
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                   min_pattern_length: 10,
                                   max_subroutines: 65_535,
                                 })

      Time.now - start_time
      optimization = result.instance_variable_get(:@subroutine_optimization)

      if optimization[:selected_count] > 0

        optimization[:savings].to_f / optimization[:selected_count]

      end
    end
  end
end

# Allow running as a standalone script
if __FILE__ == $PROGRAM_NAME
  RSpec.configure do |config|
    config.formatter = :documentation
  end

  RSpec::Core::Runner.run([$__FILE__])
end

# rubocop:enable Lint/UselessAssignment
