# frozen_string_literal: true

# Derives a 4-member TTC with shared tables (glyf/loca/cmap... stored once)
# from the fonttools TestTTF and TestOTF fixtures. Covers "TTC larger than
# two members" with a small file.
#
#   ruby corpus/derive/ttc_multi.rb [OUTPUT_DIR]
require_relative "common"

S = CorpusSfnt
ttf_v, ttf = S.parse(CorpusDerive.source_bytes("fonttools-test-ttf"))
otf_v, otf = S.parse(CorpusDerive.source_bytes("fonttools-test-otf"))

rename = lambda do |tables, family|
  tables.to_h.merge("name" => S.name_table([
                                             [3, 1, 0x409, 1, S.utf16(family)], [3, 1, 0x409, 2, S.utf16("Regular")],
                                             [3, 1, 0x409, 4, S.utf16("#{family} Regular")],
                                             [3, 1, 0x409, 6, S.utf16("#{family.delete(' ')}-Regular")]
                                           ])).to_a
end

fonts = [
  [ttf_v, ttf],
  [ttf_v, rename.call(ttf, "Shared Two")],
  [ttf_v, rename.call(ttf, "Shared Three")],
  [otf_v, otf],
]
CorpusDerive.write("ttc-4members-shared.ttc", S.build_ttc(fonts))
