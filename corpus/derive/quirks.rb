# frozen_string_literal: true

# Derives the empty-table, version-quirk and non-ASCII name fonts from the
# fonttools TestTTF fixture (MIT). Pure byte surgery via CorpusSfnt; the
# outputs are committed under corpus/derived/.
#
#   ruby corpus/derive/quirks.rb [OUTPUT_DIR]
require_relative "common"

S = CorpusSfnt
base = CorpusDerive.source_bytes("fonttools-test-ttf")
version, tables = S.parse(base)
tbl = tables.to_h

with = lambda do |changes, ver = version|
  merged = tbl.merge(changes)
  merged.delete_if { |_, v| v.nil? }
  S.build(ver, merged.to_a)
end
w = CorpusDerive.method(:write)

# --- empty tables --------------------------------------------------------
w.call("quirk-empty-optional-tables.ttf",
       with.call("GDEF" => "".b, "GSUB" => "".b, "GPOS" => "".b))
w.call("quirk-empty-name-table.ttf", with.call("name" => "".b))
w.call("quirk-empty-cmap-table.ttf", with.call("cmap" => "".b))

# --- version quirks ------------------------------------------------------
w.call("quirk-sfnt-version-true.ttf", with.call({}, "true"))
w.call("quirk-sfnt-version-otto-on-glyf.ttf", with.call({}, "OTTO"))
os2_v0 = tbl.fetch("OS/2").byteslice(0, 78).dup.tap { |t| t[0, 2] = [0].pack("n") }
w.call("quirk-os2-version-0.ttf", with.call("OS/2" => os2_v0))
head_v2 = tbl.fetch("head").dup.tap { |t| t[0, 4] = [2, 0].pack("n2") }
w.call("quirk-head-version-2.ttf", with.call("head" => head_v2))
fmt1 = S.name_table([[3, 1, 0x409, 1, S.utf16("Format One")],
                     [3, 1, 0x409, 2, S.utf16("Regular")],
                     [3, 1, 0x409, 4, S.utf16("Format One Regular")],
                     [3, 1, 0x409, 6, S.utf16("FormatOne-Regular")],
                     [3, 1, 0x8000, 1, S.utf16("Format Eins")]])
tag = S.utf16("de-DE")
# format 1: count+1 header fields, then the langTagRecord array after the
# name records; language id 0x8000 refers to langTag 0.
cnt = fmt1.unpack1("@2n")
recs_end = 6 + (cnt * 12)
strings = fmt1.byteslice(recs_end..)
fmt1_bytes = [1, cnt, recs_end + 2 + 4].pack("n3") +
  fmt1.byteslice(6, cnt * 12) + [1].pack("n") +
  [tag.bytesize, strings.bytesize].pack("n2") + strings + tag
w.call("quirk-name-format-1.ttf", with.call("name" => fmt1_bytes))

# --- non-ASCII name records (macintosh / windows platforms) ---------------
mac = lambda { |nid, s| [1, 0, 0, nid, S.mac_roman(s)] }
win = lambda { |nid, s, lid = 0x409| [3, 1, lid, nid, S.utf16(s)] }
uni = lambda { |nid, s| [0, 3, 0, nid, S.utf16(s)] }

w.call("names-mac-roman-only.ttf", with.call("name" => S.name_table([
                                                                      mac.call(1, "Café Ünïcöde"), mac.call(2, "Regular"),
                                                                      mac.call(4, "Café Ünïcöde Regular"),
                                                                      mac.call(6, "CafeUnicode-Regular"),
                                                                      mac.call(0, "© Ångström Foundry")
                                                                    ])))

w.call("names-windows-nonascii-only.ttf", with.call("name" => S.name_table([
                                                                             win.call(1, "テストフォント Тест"),
                                                                             win.call(2, "Regular"),
                                                                             win.call(4, "テストフォント Тест Regular"),
                                                                             win.call(6, "TestNonAscii-Regular"),
                                                                             win.call(9, "Designer \u{1D11E} éè"), # astral char: surrogate pair
                                                                             win.call(1, "テスト", 0x411),
                                                                             win.call(1, "Test Schrift ÄÖÜß", 0x407),
                                                                           ])))

w.call("names-mac-and-windows-mixed.ttf", with.call("name" => S.name_table([
                                                                             mac.call(1, "Mix Café"), mac.call(2, "Regular"),
                                                                             mac.call(4, "Mix Café Regular"), mac.call(6, "MixCafe-Regular"),
                                                                             win.call(1, "Mix Café (Windows)"), win.call(2, "Regular"),
                                                                             win.call(4, "Mix Café (Windows) Regular"), win.call(6, "MixCafeWin-Regular"),
                                                                             uni.call(1, "Mix Café (Unicode)"), uni.call(6, "MixCafeUni-Regular"),
                                                                             win.call(16, "Mix Étendue"), win.call(17, "Gras")
                                                                           ])))
