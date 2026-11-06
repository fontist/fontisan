# frozen_string_literal: true

# Derives the malformed WOFF / WOFF2 inputs (fontist/fontisan#159: the tiers must
# fail the same way) from the fonttools TestWOFF and TestWOFF2 fixtures.
#
#   ruby corpus/derive/malformed_woff.rb [OUTPUT_DIR]
require_relative "common"

w = CorpusDerive.method(:write)
woff = CorpusDerive.source_bytes("fonttools-test-woff")
woff2 = CorpusDerive.source_bytes("fonttools-test-woff2")

# WOFF1: 44-byte header, 20-byte directory entries (tag, offset, compLength,
# origLength, checksum). Overwrite the middle of the first deflated table
# (compLength < origLength) with 0xFF so zlib rejects the stream.
tables = woff.byteslice(12, 2).unpack1("n")
rec = (0...tables).map { |i| woff.byteslice(44 + (i * 20), 20).unpack("a4N4") }
tag, off, comp, = rec.find { |_, _, c, o| c < o }
raise "no deflated table in TestWOFF" unless tag

bad = woff.dup
bad[off + 2, comp - 2] = "\xFF".b * (comp - 2)
w.call("malformed-woff-corrupt-deflate.woff", bad)

# Zero the whole table directory.
zero = woff.dup
zero[44, tables * 20] = "\x00".b * (tables * 20)
w.call("malformed-woff-zero-table-dir.woff", zero)

w.call("malformed-woff-truncated-half.woff", woff.byteslice(0, woff.bytesize / 2))

# WOFF2: 48-byte header; totalCompressedSize at byte 20 locates the single
# brotli stream, which starts after the table directory. Overwrite the tail of
# the stream (the head of a brotli stream is a small window descriptor).
total_compressed = woff2.byteslice(20, 4).unpack1("N")
stream_start = woff2.bytesize - total_compressed
bad2 = woff2.dup
bad2[stream_start + 4, total_compressed - 4] = "\xFF".b * (total_compressed - 4)
w.call("malformed-woff2-corrupt-brotli.woff2", bad2)

# Zero the table directory (it follows the 48-byte header, 5 bytes per entry
# at minimum; zeroing 64 bytes spans the whole directory of this fixture).
zero2 = woff2.dup
zero2[48, [64, stream_start - 48].min] = "\x00".b * [64, stream_start - 48].min
w.call("malformed-woff2-zero-table-dir.woff2", zero2)

w.call("malformed-woff2-truncated-half.woff2", woff2.byteslice(0, woff2.bytesize / 2))
