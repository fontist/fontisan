#!/usr/bin/env ruby
# frozen_string_literal: true

# Comparison script for stack-aware vs normal subroutine optimization
#
# Usage:
#   ruby scripts/compare_stack_aware.rb [font_path]
#
# If no font path provided, uses NotoSans-Regular.ttf from fixtures

require_relative "../lib/fontisan"

def format_bytes(bytes)
  if bytes < 1024
    "#{bytes} B"
  elsif bytes < 1024 * 1024
    "#{(bytes / 1024.0).round(2)} KB"
  else
    "#{(bytes / (1024.0 * 1024)).round(2)} MB"
  end
end

def format_time(seconds)
  if seconds < 1
    "#{(seconds * 1000).round(1)} ms"
  else
    "#{seconds.round(2)} s"
  end
end

def measure_optimization(font_path, mode)
  puts "\n#{if mode == :none
              'Unoptimized'
            else
              mode == :normal ? 'Normal Optimization' : 'Stack-Aware Optimization'
            end}:"
  puts "=" * 60

  font = Fontisan::FontLoader.load(font_path)
  converter = Fontisan::Converters::OutlineConverter.new

  options = {
    target_format: :otf,
    optimize_subroutines: mode != :none,
    stack_aware: mode == :stack_aware,
    verbose: false,
  }

  start_time = Time.now
  result = converter.convert(font, options)
  processing_time = Time.now - start_time

  cff_size = result["CFF "].bytesize
  optimization = result.instance_variable_get(:@subroutine_optimization)

  puts "  CFF table size: #{format_bytes(cff_size)}"
  puts "  Processing time: #{format_time(processing_time)}"

  if optimization
    puts "  Patterns found: #{optimization[:pattern_count]}"
    puts "  Patterns selected: #{optimization[:selected_count]}"
    puts "  Local subroutines: #{optimization[:local_subrs].length}"
    puts "  Estimated savings: #{format_bytes(optimization[:savings])}"
    puts "  Bias: #{optimization[:bias]}"
  else
    puts "  No optimization performed"
  end

  {
    size: cff_size,
    time: processing_time,
    optimization: optimization,
  }
end

def main
  font_path = ARGV[0] || "spec/fixtures/fonts/NotoSans-Regular.ttf"

  unless File.exist?(font_path)
    puts "Error: Font file not found: #{font_path}"
    puts "Usage: ruby scripts/compare_stack_aware.rb [font_path]"
    exit 1
  end

  puts "╔═══════════════════════════════════════════════════════════════╗"
  puts "║       Stack-Aware vs Normal Optimization Comparison           ║"
  puts "╚═══════════════════════════════════════════════════════════════╝"
  puts
  puts "Font: #{font_path}"

  # Measure all three modes
  unoptimized = measure_optimization(font_path, :none)
  normal = measure_optimization(font_path, :normal)
  stack_aware = measure_optimization(font_path, :stack_aware)

  # Summary comparison
  puts "\n#{'=' * 60}"
  puts "SUMMARY COMPARISON"
  puts "=" * 60

  puts "\nFile Sizes:"
  puts "  Unoptimized:  #{format_bytes(unoptimized[:size])} (baseline)"
  puts "  Normal:       #{format_bytes(normal[:size])} (#{((normal[:size] - unoptimized[:size]) * 100.0 / unoptimized[:size]).round(2)}% change)"
  puts "  Stack-Aware:  #{format_bytes(stack_aware[:size])} (#{((stack_aware[:size] - unoptimized[:size]) * 100.0 / unoptimized[:size]).round(2)}% change)"

  puts "\nProcessing Times:"
  puts "  Unoptimized:  #{format_time(unoptimized[:time])}"
  puts "  Normal:       #{format_time(normal[:time])}"
  puts "  Stack-Aware:  #{format_time(stack_aware[:time])}"

  if normal[:optimization] && stack_aware[:optimization]
    puts "\nOptimization Metrics:"
    puts "  Patterns Found:"
    puts "    Normal:       #{normal[:optimization][:pattern_count]}"
    puts "    Stack-Aware:  #{stack_aware[:optimization][:pattern_count]}"

    puts "  Patterns Selected:"
    puts "    Normal:       #{normal[:optimization][:selected_count]}"
    puts "    Stack-Aware:  #{stack_aware[:optimization][:selected_count]}"

    puts "  Subroutines Generated:"
    puts "    Normal:       #{normal[:optimization][:local_subrs].length}"
    puts "    Stack-Aware:  #{stack_aware[:optimization][:local_subrs].length}"

    puts "\nBytes Saved (estimated):"
    puts "    Normal:       #{format_bytes(normal[:optimization][:savings])}"
    puts "    Stack-Aware:  #{format_bytes(stack_aware[:optimization][:savings])}"
  end

  puts "\n#{'=' * 60}"
  puts "ANALYSIS"
  puts "=" * 60

  # Calculate relative improvements
  normal_reduction = unoptimized[:size] - normal[:size]
  stack_aware_reduction = unoptimized[:size] - stack_aware[:size]

  puts "\nFile Size Reduction:"
  if normal_reduction.positive?
    puts "  Normal: #{format_bytes(normal_reduction)} (#{(normal_reduction * 100.0 / unoptimized[:size]).round(2)}%)"
  else
    puts "  Normal: No reduction achieved"
  end

  if stack_aware_reduction.positive?
    puts "  Stack-Aware: #{format_bytes(stack_aware_reduction)} (#{(stack_aware_reduction * 100.0 / unoptimized[:size]).round(2)}%)"
  else
    puts "  Stack-Aware: No reduction achieved"
  end

  if normal_reduction.positive? && stack_aware_reduction.positive?
    efficiency_ratio = (stack_aware_reduction.to_f / normal_reduction * 100).round(2)
    puts "\nStack-Aware Efficiency: #{efficiency_ratio}% of normal optimization"
  end

  time_overhead = ((stack_aware[:time] / unoptimized[:time] - 1) * 100).round(2)
  puts "\nProcessing Time Overhead:"
  puts "  Stack-Aware vs Unoptimized: +#{time_overhead}%"

  puts "\n#{'=' * 60}"
  puts "CONCLUSION"
  puts "=" * 60

  if stack_aware_reduction.positive?
    puts "\n✓ Stack-aware optimization achieved #{(stack_aware_reduction * 100.0 / unoptimized[:size]).round(2)}% file size reduction"
    puts "✓ Trade-off: More reliable (stack-neutral patterns only)"
    if normal_reduction > stack_aware_reduction
      diff = normal_reduction - stack_aware_reduction
      puts "✓ Cost: #{format_bytes(diff)} less compression vs normal mode"
    elsif stack_aware_reduction > normal_reduction
      diff = stack_aware_reduction - normal_reduction
      puts "✓ Bonus: #{format_bytes(diff)} more compression than normal mode!"
    else
      puts "✓ Same compression as normal mode"
    end
  else
    puts "\n⚠ Stack-aware optimization did not achieve compression for this font"
    puts "  This may indicate:"
    puts "  - Few stack-neutral patterns available"
    puts "  - Font has simple glyph structures"
    puts "  - Pattern sizes too small after stack validation"
  end

  puts
end

main if __FILE__ == $PROGRAM_NAME
