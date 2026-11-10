# frozen_string_literal: true

# Derives the fuzz-found malformed inputs (fontist/fontisan#156 card 3b). Each
# one reproduces a crash or hang the fontisan-rs fuzzing found in the Rust tier
# (1j-parsers, 1j-abi); the Rust fix is pinned by a unit test there, and the
# Ruby reference result is pinned here by the malformed goldens.
#
#   ruby corpus/derive/fuzz.rb [OUTPUT_DIR]
require_relative "common"

S = CorpusSfnt
version, tables = S.parse(CorpusDerive.source_bytes("fonttools-test-ttf"))
tbl = tables.to_h
w = CorpusDerive.method(:write)

# cmap format 12 with one group spanning 0..0xFFFFFFFF: walking it unbounded
# ran for minutes and allocated without limit (1j-parsers).
cmap = [0, 1, 3, 10, 12].pack("nnnnN")
cmap << [12, 0, 28, 0, 1, 0, 0xFFFF_FFFF, 1].pack("nnNNNNNN")
w.call("malformed-fuzz-cmap12-u32-span.ttf", S.build(version, tbl.merge("cmap" => cmap).to_a))

# CFF2 CharStrings INDEX with count 0xFFFFFFFF and offSize 0: zero-width reads
# always succeed, so the offset loop never ended (1j-parsers).
cff2 = [2, 0, 5, 0, 3, 139 + 8, 139 + 8, 17].pack("C*") + [0xFFFF_FFFF, 0].pack("NC") + ("\0" * 8)
otf = tbl.except("glyf", "loca").merge("CFF2" => cff2)
w.call("malformed-fuzz-cff2-huge-count.otf", S.build("OTTO", otf.to_a))

# TTC whose only member has a `head` directory entry at offset 0xFFFFFFF0:
# extract wrote the checksum adjustment there and grew the output to ~4 GiB
# (1j-abi).
ttc = "ttcf".b + [0x0001_0000, 1, 16].pack("NNN")
ttc << [0x0001_0000, 1, 0, 0, 0].pack("Nnnnn") << "head".b << [0, 0xFFFF_FFF0, 54].pack("NNN")
w.call("malformed-fuzz-ttc-head-offset.ttc", ttc)
