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
                                                 Fontisan::Ufo::Point.new(x: 0,
                                                                          y: 0, type: "line"),
                                                 Fontisan::Ufo::Point.new(
                                                   x: 100, y: 0, type: "line",
                                                 ),
                                                 Fontisan::Ufo::Point.new(
                                                   x: 95, y: 40, type: "offcurve",
                                                 ),
                                                 Fontisan::Ufo::Point.new(
                                                   x: 80, y: 90, type: "offcurve",
                                                 ),
                                                 Fontisan::Ufo::Point.new(
                                                   x: 50, y: 150, type: "curve",
                                                 ),
                                               ]))
      font.glyphs["g#{i}"] = g
    end
    font
  end

  def rss_mb
    # VmHWM is the true high-water mark on Linux; ps gives current RSS on
    # macOS (close enough for one short compile, labelled RSS not peak).
    if RUBY_PLATFORM.include?("linux")
      File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_f / 1024
    else
      `ps -o rss= -p #{Process.pid}`.to_f / 1024
    end
  end

  def measure(label, glyph_count: nil)
    GC.start
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    throughput = if glyph_count && elapsed.positive?
                   "#{(glyph_count / elapsed).round(0)} glyphs/s"
                 else
                   ""
                 end
    puts "#{label.ljust(40)} #{format('%10.2f ms', elapsed * 1000)}  " \
         "#{format('%8.1f MB rss', rss_mb)}  #{throughput}"
    elapsed
  end
end

if __FILE__ == $PROGRAM_NAME
  sizes = ARGV.include?("--large") ? [1000, 10_000, 65_000] : [1000, 10_000]
  sizes.each do |count|
    ufo = FontisanBench.build_synthetic_font(count)
    Dir.mktmpdir do |dir|
      FontisanBench.measure("TTF compile (#{count} glyphs)", glyph_count: count) do
        Fontisan::Ufo::Compile::TtfCompiler.new(ufo).compile(output_path: "#{dir}/a.ttf")
      end
      FontisanBench.measure("OTF compile (#{count} glyphs)", glyph_count: count) do
        Fontisan::Ufo::Compile::OtfCompiler.new(ufo).compile(output_path: "#{dir}/a.otf")
      end
      FontisanBench.measure("CFF2 OTF compile (#{count} glyphs)", glyph_count: count) do
        Fontisan::Ufo::Compile::Otf2Compiler.new(ufo).compile(output_path: "#{dir}/a-cff2.otf")
      end
    end
  end
end
