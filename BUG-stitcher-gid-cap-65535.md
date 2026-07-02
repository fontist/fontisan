# BUG: Stitcher repair pass drops 3,004 cmap entries (gid remap)

## Status

NEW — discovered 2026-07-01 with fontisan 0.4.6. Introduced by the
repair pass added alongside the compound-glyph flatten fix
(commit `73820f1`). Not yet addressed.

## Summary

The build output's post-write repair step reports:

```
repairing: 3004 cmap entries pointed to non-existent gids (max gid = 65534)
repaired: 132623 valid cmap entries retained
```

3,004 cmap entries that were correctly assembled by the Stitcher
are silently dropped because the output font's gid space caps at
65,534 and the repair step removes any cmap entry whose gid exceeds
that limit.

## Reproducer

Build essenfont with the full donor manifest (30+ donors, ~160k
codepoints in the union). The build output shows:

```
158247/158247 codepoints stitched
=== Writing Essenfont-Regular.ttf ===
  repairing: 3004 cmap entries pointed to non-existent gids (max gid = 65534)
  repaired: 132623 valid cmap entries retained
```

3,004 cps are dropped, reducing coverage from expected ~96% to ~82%.

## Root cause

The output TTF has `maxp.num_glyphs = 65535` (the 16-bit maximum).
The Stitcher assembles glyphs from 30+ donors whose combined glyph
count exceeds 65,535. When the output font is written:

1. Glyphs are assigned gids sequentially from 0 to ~160k.
2. `maxp.num_glyphs` is clamped to 65,535 (16-bit limit).
3. Any cmap entry whose gid ≥ 65,535 is now invalid (points past
   the end of the glyph array).
4. The repair pass removes those entries.

The cap of 65,535 is a hard limit of the TrueType `maxp` table
(`maxComponentElements` is uint16). Fonts with more than 65,535
glyphs require CFF (OTF) format or `maxp` version 1.5 with the
extended glyph range — but fontisan doesn't use either.

## What's lost

3,004 cmap entries are dropped. These fall into two groups:

1. **Large CJK donors** (FSung-2, NotoSansKR, NotoSansNushu):
   codepoints assigned to gids > 65,534 are silently dropped.
   Affects ~1,000 cps from Plane 2 CJK (CJK Ext I, Compat Supp)
   + ~800 cps from Hangul + ~200 cps from Nushu.

2. **Synthetic SVG donors** (Khitan, Tulu-Tigalari, etc.):
   codepoints from late-added synthetic donors get assigned gids
   beyond 65,534. Affects ~1,000 cps from chart-extracted glyphs.

## Suggested fixes

### Option A: Switch to CFF (OTF) output

CFF fonts have no 65,535 glyph cap. fontisan's `OtfCompiler` can
write OTF output. The build would produce `Essenfont-Regular.otf`
instead of `.ttf`. This is the cleanest fix but changes the output
format.

### Option B: Glyph deduplication

Many donor glyphs are identical (e.g., the .notdef glyph appears
in every donor). Deduplicating these before writing would reduce
the glyph count below 65,535. Estimated savings: ~10,000 duplicate
.notdef + whitespace glyphs.

### Option C: Subfont splitting

Split the output into multiple TTF files by Unicode plane (Plane 0,
Plane 1, Plane 2, etc.) with a TTC (TrueType Collection) wrapper.
Each subfont stays under 65,535 glyphs.

### Option D: Remove non-contributing donors

FSung-X (38,126 Plane 16 PUA cps) currently contributes zero
useful codepoints to the output. Removing it from the build would
reduce the glyph count by ~38,000, well within the 65,535 cap.

Similarly, NotoSansKR's variable font has 23,174 cps but only
11,172 are Hangul — the rest are duplicated by other donors.
Subsetting KR to just Hangul would save ~12,000 glyphs.

## Impact

Coverage drops from expected ~96% to actual ~82.76%. The 3,004
lost cps span 8+ Unicode blocks that have valid glyphs in the
donor fonts but are silently dropped at write time.

## References

- Build log with repair message: `/tmp/build-svg6.log`
- Affected blocks: CJK Ext I, CJK Compat Supp, Nushu,
  Tulu-Tigalari, Khitan Small Script (partial), Hangul (partial)
- Consumer: essenfont issue #3
