# frozen_string_literal: true

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
      puts "\n#{'=' * 60}"
      puts "Benchmarking TTF→OTF Conversion (No Optimization)"
      puts "=" * 60

      times = []
      5.times do |i|
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: false)
        end
        times << time
        puts "Run #{i + 1}: #{(time * 1000).round(2)}ms"
      end

      avg = times.sum / times.length
      min = times.min
      max = times.max
      stddev = Math.sqrt(times.sum { |t| (t - avg)**2 } / times.length)

      puts "\nStatistics:"
      puts "  Average: #{(avg * 1000).round(2)}ms"
      puts "  Min: #{(min * 1000).round(2)}ms"
      puts "  Max: #{(max * 1000).round(2)}ms"
      puts "  Std Dev: #{(stddev * 1000).round(2)}ms"
    end

    it "benchmarks conversion with optimization" do
      puts "\n#{'=' * 60}"
      puts "Benchmarking TTF→OTF Conversion (With Optimization)"
      puts "=" * 60

      times = []
      5.times do |i|
        time = Benchmark.realtime do
          converter.convert(font, target_format: :otf,
                                  optimize_subroutines: true)
        end
        times << time
        puts "Run #{i + 1}: #{(time * 1000).round(2)}ms"
      end

      avg = times.sum / times.length
      min = times.min
      max = times.max
      stddev = Math.sqrt(times.sum { |t| (t - avg)**2 } / times.length)

      puts "\nStatistics:"
      puts "  Average: #{(avg * 1000).round(2)}ms"
      puts "  Min: #{(min * 1000).round(2)}ms"
      puts "  Max: #{(max * 1000).round(2)}ms"
      puts "  Std Dev: #{(stddev * 1000).round(2)}ms"
    end

    it "compares overhead of optimization" do
      puts "\n#{'=' * 60}"
      puts "Optimization Overhead Comparison"
      puts "=" * 60

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
      overhead_pct = (overhead / baseline_avg * 100)

      puts "Baseline (no optimization): #{(baseline_avg * 1000).round(2)}ms"
      puts "With optimization: #{(optimized_avg * 1000).round(2)}ms"
      puts "Overhead: #{(overhead * 1000).round(2)}ms (#{overhead_pct.round(1)}%)"
    end
  end

  describe "Parameter Impact" do
    it "benchmarks different min_pattern_length values" do
      puts "\n#{'=' * 60}"
      puts "Impact of min_pattern_length Parameter"
      puts "=" * 60

      [5, 10, 15, 20].each do |min_length|
        time = Benchmark.realtime do
          result = converter.convert(font, {
                                       target_format: :otf,
                                       optimize_subroutines: true,
                                       min_pattern_length: min_length,
                                     })

          optimization = result.instance_variable_get(:@subroutine_optimization)
          puts "\nmin_pattern_length = #{min_length}:"
          puts "  Time: #{(time * 1000).round(2)}ms"
          puts "  Patterns found: #{optimization[:pattern_count]}"
          puts "  Patterns selected: #{optimization[:selected_count]}"
        end
      end
    end

    it "benchmarks different max_subroutines values" do
      puts "\n#{'=' * 60}"
      puts "Impact of max_subroutines Parameter"
      puts "=" * 60

      [100, 1000, 10_000, 65_535].each do |max_subrs|
        time = Benchmark.realtime do
          result = converter.convert(font, {
                                       target_format: :otf,
                                       optimize_subroutines: true,
                                       max_subroutines: max_subrs,
                                     })

          optimization = result.instance_variable_get(:@subroutine_optimization)
          puts "\nmax_subroutines = #{max_subrs}:"
          puts "  Time: #{(time * 1000).round(2)}ms"
          puts "  Patterns selected: #{optimization[:selected_count]}"
          puts "  Limited by max: #{optimization[:selected_count] >= max_subrs}"
        end
      end
    end
  end

  describe "Memory Usage" do
    it "estimates memory overhead" do
      puts "\n#{'=' * 60}"
      puts "Memory Usage Estimation"
      puts "=" * 60

      # Baseline conversion
      GC.start
      before_memory = GC.stat(:heap_allocated_pages)

      converter.convert(font, target_format: :otf, optimize_subroutines: false)

      after_baseline = GC.stat(:heap_allocated_pages)
      baseline_pages = after_baseline - before_memory

      # With optimization
      GC.start
      before_memory = GC.stat(:heap_allocated_pages)

      result = converter.convert(font, target_format: :otf,
                                       optimize_subroutines: true)

      after_optimized = GC.stat(:heap_allocated_pages)
      optimized_pages = after_optimized - before_memory

      optimization = result.instance_variable_get(:@subroutine_optimization)

      puts "Baseline memory (pages): #{baseline_pages}"
      puts "Optimized memory (pages): #{optimized_pages}"
      puts "Additional pages: #{optimized_pages - baseline_pages}"
      puts "\nOptimization results:"
      puts "  Patterns: #{optimization[:pattern_count]}"
      puts "  Selected: #{optimization[:selected_count]}"
      puts "  Subroutines: #{optimization[:local_subrs].length}"
    end
  end

  describe "Scalability" do
    it "shows performance characteristics summary" do
      puts "\n#{'=' * 60}"
      puts "Performance Characteristics Summary"
      puts "=" * 60
      puts "\nFont: #{File.basename(ttf_font_path)}"
      puts "Size: #{(File.size(ttf_font_path) / 1024.0).round(2)} KB"

      # Single run with detailed timing
      start_time = Time.now

      result = converter.convert(font, {
                                   target_format: :otf,
                                   optimize_subroutines: true,
                                   min_pattern_length: 10,
                                   max_subroutines: 65_535,
                                 })

      total_time = Time.now - start_time
      optimization = result.instance_variable_get(:@subroutine_optimization)

      puts "\nConversion Results:"
      puts "  Total time: #{(total_time * 1000).round(2)}ms"
      puts "  Optimization time: #{(optimization[:processing_time] * 1000).round(2)}ms"
      puts "  Optimization %: #{((optimization[:processing_time] / total_time) * 100).round(1)}%"

      puts "\nOptimization Metrics:"
      puts "  Patterns analyzed: #{optimization[:pattern_count]}"
      puts "  Subroutines created: #{optimization[:selected_count]}"
      puts "  Estimated savings: #{optimization[:savings]} bytes"
      puts "  CFF bias: #{optimization[:bias]}"

      if optimization[:selected_count] > 0
        puts "\nEfficiency:"
        bytes_per_subr = optimization[:savings].to_f / optimization[:selected_count]
        puts "  Bytes saved per subroutine: #{bytes_per_subr.round(2)}"
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
