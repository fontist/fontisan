# frozen_string_literal: true

# Benchmark: large font compilation performance.
#
# Measures the time taken to compile a synthetic large UFO font into
# TTF, OTF, and CFF2 OTF. Catches regressions in the charstring
# pipeline and the table builders.

require "tmpdir"
require "fontisan"
require "fontisan/ufo/compile"

module FontisanBench
  module_function

  def build_synthetic_font(num_glyphs)
    font = Fontisan::Ufo::Font.new
    font.info.family_name = "Bench"
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")

    num_glyphs.times do |i|
      g = Fontisan::Ufo::Glyph.new(name: "g#{i}")
      g.width = 500
      g.add_unicode(0xE000 + i) if i < 0x1000
      g.add_contour(Fontisan::Ufo::Contour.new([
                                                 Fontisan::Ufo::Point.new(x: 0, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 100, y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(x: 100, y: 100, type: "offcurve"),
                                                 Fontisan::Ufo::Point.new(x: 50, y: 150, type: "curve"),
                                               ]))
      font.glyphs["g#{i}"] = g
    end
    font
  end

  def measure(label)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts format("%-40<label>s %8.<elapsed>.2f ms", label: label, elapsed: elapsed * 1000)
    elapsed
  end
end

if __FILE__ == $PROGRAM_NAME
  ufo = FontisanBench.build_synthetic_font(1000)

  Dir.mktmpdir do |dir|
    FontisanBench.measure("TTF compile (1000 glyphs)") do
      Fontisan::Ufo::Compile::TtfCompiler.new(ufo).compile(output_path: "#{dir}/a.ttf")
    end
    FontisanBench.measure("OTF compile (1000 glyphs)") do
      Fontisan::Ufo::Compile::OtfCompiler.new(ufo).compile(output_path: "#{dir}/a.otf")
    end
    FontisanBench.measure("CFF2 OTF compile (1000 glyphs)") do
      Fontisan::Ufo::Compile::Otf2Compiler.new(ufo).compile(output_path: "#{dir}/a-cff2.otf")
    end
  end

  Dir.mktmpdir do |dir|
    ufo_big = FontisanBench.build_synthetic_font(10_000)
    FontisanBench.measure("TTF compile (10k glyphs)") do
      Fontisan::Ufo::Compile::TtfCompiler.new(ufo_big).compile(output_path: "#{dir}/a.ttf")
    end
    FontisanBench.measure("CFF2 OTF compile (10k glyphs)") do
      Fontisan::Ufo::Compile::Otf2Compiler.new(ufo_big).compile(output_path: "#{dir}/a-cff2.otf")
    end
  end
end
