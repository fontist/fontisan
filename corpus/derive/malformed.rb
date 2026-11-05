# frozen_string_literal: true

# Derives the malformed-input set from the fonttools TestTTF fixture.
#
#   ruby corpus/derive/malformed.rb [OUTPUT_DIR]
require_relative "common"

S = CorpusSfnt
base = CorpusDerive.source_bytes("fonttools-test-ttf")
w = CorpusDerive.method(:write)

w.call("malformed-truncated-10.ttf", base.byteslice(0, 10))
w.call("malformed-truncated-100.ttf", base.byteslice(0, 100))
w.call("malformed-truncated-half.ttf", base.byteslice(0, base.bytesize / 2))
w.call("malformed-garbage.ttf", Random.new(156).bytes(512))
w.call("malformed-empty.ttf", "".b)

# First table-directory entry (12-byte header, then tag/checksum/offset/len):
# point its offset far past the end of the file.
off = base.dup
off[12 + 8, 4] = [base.bytesize + 4096].pack("N")
w.call("malformed-bad-table-offset.ttf", off)

# Wrong per-table checksum for 'glyf' and wrong head.checkSumAdjustment.
bad = base.dup
num = bad.byteslice(4, 2).unpack1("n")
num.times do |i|
  rec = 12 + (i * 16)
  next unless bad.byteslice(rec, 4) == "glyf"

  bad[rec + 4, 4] = [bad.byteslice(rec + 4, 4).unpack1("N") ^ 0xDEADBEEF].pack("N")
end
head_off = nil
num.times do |i|
  rec = 12 + (i * 16)
  next unless bad.byteslice(rec, 4) == "head"

  head_off = bad.byteslice(rec + 8, 4).unpack1("N")
end
bad[head_off + 8, 4] = [0x12345678].pack("N")
w.call("malformed-bad-checksum.ttf", bad)

# numTables larger than the file can hold.
nt = base.dup
nt[4, 2] = [0xFFFF].pack("n")
w.call("malformed-bad-num-tables.ttf", nt)
