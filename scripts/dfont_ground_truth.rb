# frozen_string_literal: true

# Ground truth for the dfont conversion surfaces (#192 gap 5): what the Ruby
# tier raises for each convert target on a dfont source.
require "fontisan"

path = "../fontisan-rs/.corpus/fontisan/corpus/fonts/TestDFONT.dfont"

def try_convert(path, target, out)
  Fontisan::Reference.convert(path, to: target, output: out)
  size = File.size(out)
  if target == :dfont
    same = File.binread(out) == File.binread(path)
    puts "dfont->#{target}: #{size} bytes, byte-identical to input: #{same}"
  else
    puts "dfont->#{target}: ok, #{size} bytes"
  end
rescue StandardError => e
  puts "dfont->#{target} raise #{e.class}: #{e.message[0, 90]}"
end

try_convert(path, :dfont, "/tmp/dfont-out.dfont")
try_convert(path, :ttc, "/tmp/dfont-out.ttc")
try_convert(path, :otc, "/tmp/dfont-out.otc")
try_convert(path, :woff2, "/tmp/dfont-out.woff2")
try_convert(path, :ttf, "/tmp/dfont-out.ttf")
