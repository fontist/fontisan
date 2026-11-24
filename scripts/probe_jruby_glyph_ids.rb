# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "fontisan"

path = ARGV[0] || File.expand_path("../../fontisan-rs/.corpus/fontisan/corpus/fonts/SourceSans3-Regular.otf.woff2", __dir__)
options = { text: "AB a." }

def show(label)
  result = yield
  puts "#{label}: #{result.inspect}"
rescue StandardError, ScriptError => e
  puts "#{label}: RAISE #{e.class}: #{e.message.to_s[0, 120]}"
end

show("Ffi.available?") { Fontisan::Ffi.available? }
show("ops include glyph_ids") { Fontisan::Ffi::OPERATIONS.include?(:glyph_ids) }
show("BYTE_OPERATIONS") { Fontisan::ByteOps::BYTE_OPERATIONS.inspect }
show("path") { path }
show("File.file?") { File.file?(path) }
show("detect_format") { Fontisan::FontLoader.detect_format(path) }
show("head") { File.binread(path, 8).unpack1("A8") }
show("Ffi.supports?(2arg)") { Fontisan::Ffi.supports?(:glyph_ids, path) }
show("Ffi.supports?(read)") { Fontisan::Ffi.supports?(:read, path) }
show("Ffi.supports?(glyph_ids, nil path)") { Fontisan::Ffi.supports?(:glyph_ids, nil) }
show("Ffi.supports?(glyph_ids, ttf path)") do
  ttf = File.expand_path("../../fontisan-rs/.corpus/fontisan/corpus/fonts/NotoSans-Regular.ttf", __dir__)
  Fontisan::Ffi.supports?(:glyph_ids, ttf)
end
show("arity") { Fontisan::Ffi.method(:supports_options?).arity }
show("Ffi.supports_options?(direct)") { Fontisan::Ffi.supports_options?(:glyph_ids, options, path) }
show("Engine.available?(:ffi)") { Fontisan::Engine.available?(:ffi) }
show("Engine.resolve(auto)") do
  ENV.delete("FONTISAN_ENGINE")
  Fontisan::Engine.reset!
  Fontisan::Engine.resolve(:glyph_ids, path, options)
end
show("Engine.resolve(forced ffi)") do
  ENV["FONTISAN_ENGINE"] = "ffi"
  Fontisan::Engine.reset!
  v = Fontisan::Engine.resolve(:glyph_ids, path, options)
  ENV.delete("FONTISAN_ENGINE")
  Fontisan::Engine.reset!
  v
end
show("Reference.glyph_ids outcome") do
  ENV["FONTISAN_ENGINE"] = "ffi"
  Fontisan::Engine.reset!
  v = begin
    Fontisan::Reference.glyph_ids(path, text: "AB a.")
    :ok
  rescue StandardError => e
    "#{e.class}: #{e.message[0, 80]}"
  end
  ENV.delete("FONTISAN_ENGINE")
  Fontisan::Engine.reset!
  v
end
show("served_by") { Fontisan::Engine.served_by(:glyph_ids) }
