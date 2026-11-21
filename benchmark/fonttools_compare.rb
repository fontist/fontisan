# frozen_string_literal: true

# Benchmark: fontisan's TTF/OTF compile vs ufo2ft (fontTools), the
# industry UFO compiler. Both consume the SAME on-disk UFO (written
# from one synthetic font, TODO.remaining/20), so the comparison is
# wall time and output size on identical input. Requires python3 with
# ufo2ft; the script reports SKIP and keeps running without it.

require "open3"
require "tmpdir"
require "fontisan"
require_relative "compile_benchmark"

module FontisanBench
  module_function

  # Minimal UFO 3 writer: enough structure for both compilers
  # (metainfo, fontinfo, contents.plist, one .glif per glyph).
  def write_ufo(font, dir)
    require "fileutils"
    FileUtils.mkdir_p(dir)
    meta = File.join(dir, "metainfo.plist")
    File.write(meta, Fontisan::Ufo::Plist.emit(
                       "formatVersion" => 3, "creator" => "fontisan-bench",
                     ))
    File.write(File.join(dir, "fontinfo.plist"), Fontisan::Ufo::Plist.emit(
                                                   "familyName" => font.info.family_name,
                                                   "unitsPerEm" => font.info.units_per_em,
                                                   "ascender" => 800, "descender" => -200
                                                 ))
    glyphs_dir = File.join(dir, "glyphs")
    Dir.mkdir(glyphs_dir)
    File.write(File.join(dir, "layercontents.plist"),
               Fontisan::Ufo::Plist.emit([["public.default", "glyphs"]]))
    contents = font.glyphs.to_h { |name, _| [name, "#{name}.glif"] }
    File.write(File.join(glyphs_dir, "contents.plist"),
               Fontisan::Ufo::Plist.emit(contents))
    font.glyphs.each do |name, glyph|
      File.write(File.join(glyphs_dir, "#{name}.glif"), glyph.to_glif)
    end
    dir
  end

  def python_has_ufo2ft?
    _out, err, status = Open3.capture3("python3", "-c", "import ufo2ft")
    warn "SKIP: ufo2ft not importable (#{err.strip.lines.first})" unless status.success?
    status.success?
  end

  def python_compile(entry, ufo_dir, out_path)
    script = <<~PY
      from defcon import Font
      from ufo2ft import #{entry}
      ufo = Font("#{ufo_dir}")
      font = #{entry}(ufo)
      font.save("#{out_path}")
    PY
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _out, err, status = Open3.capture3("python3", "-c", script)
    raise "ufo2ft failed: #{err.lines.last(3).join}" unless status.success?

    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end
end

if __FILE__ == $PROGRAM_NAME
  exit 0 unless FontisanBench.python_has_ufo2ft?

  count = ARGV.include?("--large") ? 10_000 : 1000
  ufo = FontisanBench.build_synthetic_font(count)
  Dir.mktmpdir do |dir|
    ufo_dir = FontisanBench.write_ufo(ufo, File.join(dir, "Bench.ufo"))
    puts format("%d glyphs, same on-disk UFO for both compilers", count)
    [
      ["TTF", "compileTTF", Fontisan::Ufo::Compile::TtfCompiler, "a.ttf"],
      ["OTF", "compileOTF", Fontisan::Ufo::Compile::OtfCompiler, "a.otf"],
    ].each do |name, entry, compiler, out_name|
      fontisan_out = File.join(dir, "fontisan-#{out_name}")
      t = FontisanBench.measure("fontisan #{name} compile (#{count} glyphs)",
                                glyph_count: count) do
        compiler.new(Fontisan::Ufo::Font.open(ufo_dir)).compile(output_path: fontisan_out)
      end
      t2 = FontisanBench.measure("ufo2ft  #{name} compile (#{count} glyphs)",
                                 glyph_count: count) do
        FontisanBench.python_compile(entry, ufo_dir, File.join(dir, "ufo2ft-#{out_name}"))
      end
      ours = File.size(fontisan_out)
      theirs = File.size(File.join(dir, "ufo2ft-#{out_name}"))
      factor = t2.positive? ? format("%5.2fx", t2 / t) : "n/a"
      puts "#{"#{name} output size".ljust(40)} #{ours} B vs #{theirs} B  " \
           "ufo2ft/fontisan time #{factor}"
    end
  end
end
