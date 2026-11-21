# frozen_string_literal: true

# Benchmark: collection assembly performance.
#
# Compiles N synthetic UFO fonts to TTF, then packs them into a TTC
# with the shared-table deduplicator, measuring assembly time and the
# space the dedup saves. Complements compile_benchmark.rb
# (TODO.remaining/20: "Collection time: multi-font -> TTC/OTC").

require "tmpdir"
require "fontisan"
require_relative "compile_benchmark"

module FontisanBench
end

if __FILE__ == $PROGRAM_NAME
  face_counts = ARGV.include?("--large") ? [4, 8, 16] : [4, 8]
  face_counts.each do |count|
    Dir.mktmpdir do |dir|
      paths = Array.new(count) do |i|
        ufo = FontisanBench.build_synthetic_font(1000)
        ufo.info.family_name = "Bench#{i}"
        File.join(dir, "face#{i}.ttf").tap do |path|
          Fontisan::Ufo::Compile::TtfCompiler.new(ufo).compile(output_path: path)
        end
      end
      fonts = paths.map { |p| Fontisan::FontLoader.load(p) }
      out = File.join(dir, "packed.ttfc")
      raw = paths.sum { |p| File.size(p) }
      FontisanBench.measure("TTC pack (#{count} faces, ~1000 glyphs each)",
                            glyph_count: 1000 * count) do
        Fontisan::Collection::Builder.new(fonts).build_to_file(out)
      end
      packed = File.size(out)
      smaller = (1 - packed.to_f / raw) * 100
      puts "collection size".ljust(40) +
        "#{raw} B raw  #{packed} B packed  #{smaller.round(1)}% smaller"
    end
  end
end
