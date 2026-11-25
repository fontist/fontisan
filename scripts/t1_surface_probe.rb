# frozen_string_literal: true

# Corrupt-PFB surface probe: which inputs fail at PFB-parse time vs reach the
# Type1Font object (and its post-parse NoMethodError surface).
require "fontisan"

def surf(name, bytes)
  File.binwrite("/tmp/probe.pfb", bytes)
  Fontisan::Reference.read("/tmp/probe.pfb")
  puts "#{name}: OK?!"
rescue StandardError => e
  puts "#{name}: #{e.class}: #{e.message[0, 130]}"
end

orig = File.binread("corpus/fonts/fonttools-test-t1-pfb/TestT1-Regular.pfb")

bad = orig.dup
bad.setbyte(0, 0x7F)
surf("bad marker", bad)
surf("truncated-10", orig[0, 10])
surf("truncated-half", orig[0, orig.bytesize / 2])
surf("header-only", orig[0, 6])
surf("binary-seg-claimed-past-eof", orig[0, 6] + [0x80, 0x02, 0xFF, 0xFF, 0x00, 0x00].pack("C6"))
