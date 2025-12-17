#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/fontisan"

def measure_font(font_path, options = {})
  puts "\n#{'=' * 80}"
  puts "Analyzing: #{File.basename(font_path)}"
  puts "=" * 80

  font = Fontisan::FontLoader.load(font_path)
  converter = Fontisan::Converters::OutlineConverter.new

  # Get glyph count
  maxp = font.table("maxp")
  num_glyphs = maxp.num_glyphs
  puts "Glyphs: #{num_glyphs}"

  # Measure without optimization
  puts "\n[1/2] Converting without optimization..."
  start_time = Time.now
  tables_unopt = converter.convert(font,
                                   target_format: :otf,
                                   optimize_subroutines: false)
  time_unopt = Time.now - start_time
  size_unopt = tables_unopt["CFF "].bytesize

  # Measure with optimization
  puts "[2/2] Converting with optimization..."
  start_time = Time.now
  tables_opt = converter.convert(font,
                                 target_format: :otf,
                                 optimize_subroutines: true,
                                 min_pattern_length: options[:min_pattern_length] || 10,
                                 max_subroutines: options[:max_subroutines] || 1000,
                                 verbose: false)
  time_opt = Time.now - start_time
  size_opt = tables_opt["CFF "].bytesize

  # Get optimization details
  opt_result = tables_opt.instance_variable_get(:@subroutine_optimization)

  # Calculate metrics
  savings = size_unopt - size_opt
  reduction_percent = (savings * 100.0 / size_unopt).round(2)
  size_per_glyph_unopt = (size_unopt.to_f / num_glyphs).round(1)
  size_per_glyph_opt = (size_opt.to_f / num_glyphs).round(1)

  # Display results
  puts "\n#{'-' * 80}"
  puts "RESULTS"
  puts "-" * 80
  puts "File Sizes:"
  puts "  Without optimization: #{format('%10d', size_unopt)} bytes (#{size_per_glyph_unopt} bytes/glyph)"
  puts "  With optimization:    #{format('%10d', size_opt)} bytes (#{size_per_glyph_opt} bytes/glyph)"
  puts "  Bytes saved:          #{format('%10d', savings)} bytes"
  puts "  Reduction:            #{format('%9.2f', reduction_percent)}%"

  puts "\nProcessing Time:"
  puts "  Without optimization: #{format('%.2f', time_unopt)} seconds"
  puts "  With optimization:    #{format('%.2f', time_opt)} seconds"
  puts "  Overhead:             #{format('%.2f', time_opt - time_unopt)} seconds"

  if opt_result
    puts "\nOptimization Details:"
    puts "  Patterns found:       #{format('%10d', opt_result[:pattern_count])}"
    puts "  Patterns selected:    #{format('%10d', opt_result[:selected_count])}"
    puts "  Subroutines:          #{format('%10d', opt_result[:local_subrs].length)}"
    puts "  CFF bias:             #{format('%10d', opt_result[:bias])}"
    puts "  Est. bytes saved:     #{format('%10d', opt_result[:savings])}"
  end

  {
    font: File.basename(font_path),
    num_glyphs: num_glyphs,
    size_unopt: size_unopt,
    size_opt: size_opt,
    savings: savings,
    reduction_percent: reduction_percent,
    time_unopt: time_unopt,
    time_opt: time_opt,
    patterns_found: opt_result[:pattern_count],
    patterns_selected: opt_result[:selected_count],
    subroutines: opt_result[:local_subrs].length,
  }
end

def print_summary(results)
  return if results.empty?

  puts "\n\n#{'=' * 80}"
  puts "SUMMARY TABLE"
  puts "=" * 80
  puts format("%-30s %8s %12s %12s %10s %8s",
              "Font", "Glyphs", "Before", "After", "Saved", "Reduction")
  puts "-" * 80

  results.each do |r|
    puts format("%-30s %8d %12d %12d %10d %7.2f%%",
                r[:font], r[:num_glyphs],
                r[:size_unopt], r[:size_opt],
                r[:savings], r[:reduction_percent])
  end

  # Calculate averages
  avg_reduction = (results.sum { |r| r[:reduction_percent] } / results.length).round(2)
  total_saved = results.sum { |r| r[:savings] }

  puts "-" * 80
  puts "Average reduction: #{avg_reduction}%"
  puts "Total bytes saved: #{total_saved} bytes"
  puts "=" * 80
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  font_paths = ARGV

  if font_paths.empty?
    # Use fixtures if no arguments provided
    fixtures_dir = File.join(File.dirname(__FILE__), "..", "spec", "fixtures", "fonts")
    font_paths = Dir.glob(File.join(fixtures_dir, "*.ttf"))
  end

  if font_paths.empty?
    puts "Usage: ruby #{__FILE__} <font1.ttf> [font2.ttf ...]"
    puts "   or: ruby #{__FILE__}  (uses fixture fonts)"
    exit 1
  end

  results = []
  font_paths.each do |path|
    result = measure_font(path)
    results << result
  rescue StandardError => e
    puts "\nERROR: Failed to process #{File.basename(path)}"
    puts "  #{e.message}"
  end

  print_summary(results)
end
