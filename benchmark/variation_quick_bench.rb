# frozen_string_literal: true

require "benchmark"
require "fontisan"

# Load variable font
FONT_PATH = "spec/fixtures/SourceSans3VF-Roman.otf"

unless File.exist?(FONT_PATH)
  puts "Error: Test font not found at #{FONT_PATH}"
  exit 1
end

font = Fontisan::FontLoader.load(FONT_PATH)

puts "=== Variable Font Parallel Performance ==="
puts "Font: #{FONT_PATH}"
puts

# Test coordinates
coords = Array.new(4) { |i| { "wght" => 300 + i * 200 } }
puts "Generating #{coords.size} instances"
puts

# Sequential (1 thread)
seq_gen = Fontisan::Variation::ParallelGenerator.new(font, threads: 1)
seq_time = Benchmark.realtime do
  seq_gen.generate_batch(coords)
end

# Parallel (4 threads)
par_gen = Fontisan::Variation::ParallelGenerator.new(font, threads: 4)
par_time = Benchmark.realtime do
  par_gen.generate_batch(coords)
end

puts "Sequential (1 thread): #{format('%.3f', seq_time)}s"
puts "Parallel (4 threads):  #{format('%.3f', par_time)}s"
puts "Speedup: #{format('%.2f', seq_time / par_time)}x"
puts

# Cache stats
cache = Fontisan::Variation::ThreadSafeCache.new
5.times { cache.fetch("test_#{rand(100)}") { rand } }

puts "Cache Statistics:"
puts cache.statistics.inspect
