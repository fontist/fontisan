# BUG: Stitcher drops isolated codepoints from NotoSansCuneiform (U+12399)

## Status

NEW — discovered 2026-07-01. Not yet addressed. Same class as the
earlier Plane 1 drop bugs (BUG-stitcher-drops-plane1-codepoints.md)
but at a different gid position (gid 925 of 1238).

## Reproducer

```ruby
require "fontisan"

src = Fontisan::FontLoader.load("NotoSansCuneiform-Regular.ttf")
cmap = src.table("cmap").unicode_mappings
# U+12399 → gid 925 (font has 1239 glyphs total)

stitcher = Fontisan::Stitcher.new
stitcher.add_source(:cuneiform, src)
stitcher.include_notdef(from: :cuneiform)
stitcher.include_codepoints([0x12399], from: :cuneiform)
stitcher.write_to("/tmp/out.ttf", format: :ttf)

out = Fontisan::FontLoader.load("/tmp/out.ttf")
out.table("cmap").unicode_mappings.key?(0x12399)
# => false  ← SILENTLY DROPPED
```

## Source font

- File: `NotoSansCuneiform-Regular.ttf` (essenfont repo)
- num_glyphs: 1239
- cmap size: 1238
- U+12399 → gid 925 (well within range, NOT at the top end)

## Other donors affected

Same pattern may affect other donors with similar cmap topology.
Worth running the full donor_audit + coverage gap analysis to
identify all affected codepoints.

## Impact

essenfont output is missing U+12399 (Cuneiform) and possibly other
codepoints from various donors. Each donor with a similar gid layout
may lose 1-N codepoints silently.

## Suggested investigation

The O(1) per-glyph extraction path (commit `f07e788`) may still have
edge cases. gid 925 isn't at the boundary of the font — the drop is
not a "top-end gid" issue like Kedebideri. This is an isolated drop
in the middle of the gid range.

Check the glyph at gid 925 in the source — is it empty, a composite,
or otherwise different from its neighbors? The `Convert::FromBinData`
fix that addressed the `next unless simple` issue may still have
gaps for certain glyph types.
