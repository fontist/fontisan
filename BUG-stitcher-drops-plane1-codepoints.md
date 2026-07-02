# BUG: Stitcher silently drops Plane 1 codepoints from some sources (and partial Plane 1 loss from others)

## RESOLVED in fontisan 0.4.2 (PR #53)

All four failure modes are fixed. Final status:

| Failure | 0.4.0 | 0.4.1 | 0.4.2 |
|---|---|---|---|
| Lentariso TTF Plane 1 (Imperial Aramaic, Phoenician, Sidetic) | broken | fixed | **fixed** ✓ |
| Kedebideri TTF top gids (Beria Erfe U+16EB5–B8, U+16ED0–D3) | broken | fixed | **fixed** ✓ |
| Tangut OTF/CFF Plane 1 (NotoSerifTangut) | ok | broken | **fixed** ✓ |
| CBDT passthrough (NotoColorEmoji) | ok | ok | **fixed** ✓ |

### Root cause (PR #53)

`Convert::FromBinData` had `next unless simple` which skipped empty
glyphs, breaking gid → array index alignment. The O(1) per-glyph
extraction introduced in 0.4.1 (`f07e788`) relied on that alignment
and silently dropped cps whose gids mapped to skipped slots.

PR #53 contains 3 commits:

1. **`Convert::FromBinData`**: removed `next unless simple` — always
   adds glyph to UFO (even if empty), maintaining gid → array index
   alignment. **Root cause fix for both the original TTF bug and the
   CFF regression.**
2. **`Stitcher::Source#extract_cff_glyph_safe(gid)`**: for CFF
   sources, falls back to full UFO conversion (which now has no
   gaps).
3. **Regression spec**: OTF/CFF Tangut test added to
   `spec/fontisan/stitcher/cmap_preservation_spec.rb` — verifies
   Tangut codepoints from `NotoSerifTangut.otf` survive in output.
4. **GPOS kern writer** (TODO 08 partial): new `Compile::Gpos`
   module builds minimal GPOS table from UFO kerning pairs.

### Consumer-side validation (essenfont)

Build with fontisan 0.4.2 + the full donor manifest produces:

- 65,535 glyphs / 45.9MB
- 181,515 cmap entries (was 159,764 in issue #3, +21,751)
- 59.75% Unicode 17 coverage (was 53.00%, +6.75 pp)
- 53 blocks complete (was 49)

All affected donors round-trip 100%:

| Donor | Block | CMAP → output |
|---|---|---|
| Lentariso | Imperial Aramaic U+10840–1085F | 31/31 |
| Lentariso | Phoenician U+10900–1091F | 29/29 |
| Lentariso | Sidetic U+10940–1095F | 26/26 |
| Kedebideri | Beria Erfe U+16EA0–16EDF | 50/50 |
| NotoSerifTangut (OTF/CFF) | Tangut U+17000–187FF | 6136/6136 |
| NotoSerifTangut | Tangut Components U+18800–18AFF | 768/768 |
| NotoColorEmoji (CBDT) | Emoticons U+1F600–1F64F | 80/80 |

The sections below are preserved for historical reference.

---

## Summary

Two distinct failures in `Fontisan::Stitcher` (fontisan 0.4.0) when
stitching codepoints from certain TTF/OTF sources into a target TTF:

1. **Total Plane 1 drop** — for sources that have cmap entries in
   Plane 1 (U+10000..U+1FFFF), the Stitcher writes **none** of them
   into the output font, even though the donor's cmap loads
   correctly via `Fontisan::FontLoader.load`.
2. **Partial upper-end drop** — for some sources, a small contiguous
   run of the highest-cp Plane 1 entries is dropped, while the rest
   of the block is preserved.


Both failures are silent — no exception, no warning. The output font
is missing the affected codepoints without any indication.

## Reproducers

### Bug 1 — Lentariso (total Plane 1 drop)

```ruby
require "fontisan"

src = Fontisan::FontLoader.load("references/input-fonts/Lentariso-Regular.ttf")
cmap = src.table("cmap")
maps = cmap.unicode_mappings
plane1_cps = maps.keys.select { |cp| cp >= 0x10000 && cp <= 0x1FFFF }
# plane1_cps.size == 1934

stitcher = Fontisan::Stitcher.new
stitcher.add_source(:lentariso, src)
stitcher.include_notdef(from: :lentariso)
stitcher.include_codepoints(plane1_cps, from: :lentariso)
stitcher.write_to("/tmp/out.ttf", format: :ttf)

out = Fontisan::FontLoader.load("/tmp/out.ttf")
out_plane1 = out.table("cmap").unicode_mappings.keys
                .count { |cp| cp >= 0x10000 && cp <= 0x1FFFF }
# out_plane1 == 0
```

Sub-ranges showing the same pattern:
- U+10840..U+1085F (Imperial Aramaic): 31 cps in donor → **0 in output**
- U+10900..U+1091F (Phoenician): 29 cps in donor → **0 in output**
- U+10940..U+1095F (Sidetic): 26 cps in donor → **0 in output**

Other donors with Plane 1 coverage work correctly:
- `NewGardiner.ttf` (4,537 Plane 1 cps) → all 10/10 stitched in spot-check
- `references/input-fonts/UniHieroglyphica.ttf` (Egyptian Hieroglyphs Ext-A) → all 4,000/4,000 stitched

### Bug 2 — Kedebideri (partial upper-end drop)

```ruby
require "fontisan"

src = Fontisan::FontLoader.load("references/input-fonts/Kedebideri-Regular.ttf")
cmap = src.table("cmap")
maps = cmap.unicode_mappings
beria_erfe = maps.keys.select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }
# beria_erfe.size == 50

stitcher = Fontisan::Stitcher.new
stitcher.add_source(:kedebideri, src)
stitcher.include_notdef(from: :kedebideri)
stitcher.include_codepoints(beria_erfe, from: :kedebideri)
stitcher.write_to("/tmp/out.ttf", format: :ttf)

out = Fontisan::FontLoader.load("/tmp/out.ttf")
out_beria = out.table("cmap").unicode_mappings.keys
              .select { |cp| cp >= 0x16EA0 && cp <= 0x16EDF }
# out_beria.size == 42 (8 dropped)
```

The 8 dropped codepoints (always the same set):
- `U+16EB5`, `U+16EB6`, `U+16EB7`, `U+16EB8` (consecutive)
- `U+16ED0`, `U+16ED1`, `U+16ED2`, `U+16ED3` (consecutive)

These all map to **gids 341–348** in the source font, which is the
top end of the source's gid range (2..348). Dropped gids span the
topmost consecutive range of the cmap; the gap at gid 340 in the
source cmap (a missing glyph) precedes the first dropped range.

## Expected

All codepoints present in the source font's cmap should appear in the
stitched output's cmap, with the same or remapped glyph references.

## Actual

- Lentariso: **0 / 1934** Plane 1 codepoints make it to output (100% loss)
- Kedebideri: **42 / 50** Beria Erfe codepoints in output (16% loss, top-end)

## Observed patterns

- **Only Plane 1 is affected**. Plane 0 (BMP) codepoints from the
  same sources work fine. Plane 2+ codepoints (FSung-2, ~61,000 cps
  in CJK Extension B-E) work fine.
- **The total-drop case (Lentariso) is consistent across multiple
  runs** — every Plane 1 cp is dropped, not just some.
- **The partial-drop case (Kedebideri) drops exactly the topmost
  consecutive range of cmap gids** that correspond to Plane 1 entries
  whose gids are adjacent.
- Other Plane 1 sources work fine (NewGardiner, UniHieroglyphica),
  so the bug is not a blanket "Plane 1 unsupported" — something about
  the cmap structure or font topology triggers it.

## What's been ruled out

- cmap gids exceeding `maxp.num_glyphs` — verified all source gids
  are within num_glyphs for both Lentariso (maxp=6063, cmap=5767)
  and Kedebideri (maxp=380, cmap=347).
- File format / validation — both sources load without warning via
  `Fontisan::FontLoader.load`; their cmaps are introspectable and
  show all expected entries.
- Lentariso Plane 0 cps work (e.g., U+0041 → 'A' round-trips).
- FSung-2's Plane 2 cps (CJK Ext B, ~61k entries) work end-to-end.

## Suggested investigation directions

1. **cmap format detection** — sources may be reported as format 4
   (BMP-only) by fontisan's parser when they actually have a format
   12 subtable. If the Stitcher writes only format 4 to the output,
   all Plane 1 entries would be dropped.
2. **`Stitcher::Source#bitmap_mode`** — added in fontisan 0.4 (per
   CHANGELOG entry for the recent Stitcher rewrite). If Lentariso is
   misclassified as `:cbdt` or `:none` despite being a pure `glyf`
   source, its cmap could be ignored or partially processed.
3. **gid adjacency in cmap** — the Kedebideri drop (gids 341–348)
   sits at the topmost consecutive run of cmap gids. If the Stitcher
   has a cutoff based on "n gids before the cmap max gid", this
   could explain it. The exact mechanism is unclear without reading
   the Stitcher internals.
4. **Lookback into Stitcher's `assemble_cmap`** — the function that
   merges source cmaps into the output cmap is the most likely site
   of the bug. Check whether it iterates source cmap entries
   sorted by glyph id or by codepoint, and whether it has any
   boundary conditions on either sort key.

## Impact

- **essenfont** (this project's v0.1.0 output font) silently loses
  86+ codepoints in Sidetic / Imperial Aramaic / Phoenician, and 8
  in Beria Erfe. Coverage in `scripts/coverage_report.rb` shows the
  affected blocks as 0% (or partial), even though the source fonts
  contain valid glyphs.
- Any downstream consumer of the Stitcher that combines Plane 1
  donors is affected.

## Related

- fontisan 0.4.0 added single-source CBDT/CBLC passthrough (commit
  `b612058`); this Stitcher bug may have been introduced in the
  same refactor. If so, the fix should land in 0.4.x.

## Test fixtures

The above reproducers use donor fonts committed to the essenfont
repo at `references/input-fonts/`:
- `Lentariso-Regular.ttf` (Bryndan W. Meyerholt, OFL, sha256 514ac442c9c5c361625da0755e84baaee36bbafe098138312f5285c3bd2fa0d3)
- `Kedebideri-Regular.ttf` (SIL International, OFL, sha256 f95907a8c39c68d557c2264fcf593a858eb4751cd5e0c3c7c53e1ef354444064)

Both files are also available from the upstream sources documented in
`essenfont/references/input-fonts/ATTRIBUTIONS.md`.

## Reporter

essenfont project, issue #3 (https://github.com/fontist/essenfont/issues/3)

## Regression introduced by the fix (2026-06-30)

The `feature/stitcher-perf` branch fixes the Lentariso + Kedebideri
bugs but introduces a **new** silent Plane 1 drop for OTF/CFF sources.

### New reproducer

```ruby
require "fontisan"

# NotoSerifTangut is OTF (CFF outlines, no glyf table)
src = Fontisan::FontLoader.load("NotoSerifTangut-Regular.otf")
cmap = src.table("cmap")
maps = cmap.unicode_mappings
tangut = maps.keys.select { |cp| cp >= 0x17000 && cp <= 0x187FF }
# tangut.size == 6136

stitcher = Fontisan::Stitcher.new
stitcher.add_source(:tangut, src)
stitcher.include_notdef(from: :tangut)
stitcher.include_codepoints(tangut.first(10), from: :tangut)
stitcher.write_to("/tmp/out.ttf", format: :ttf)

out = Fontisan::FontLoader.load("/tmp/out.ttf")
outmaps = out.table("cmap").unicode_mappings
present = tangut.first(10).count { |cp| outmaps.key?(cp) }
# present == 0  ← ALL DROPPED
```

Source has tables: `["CFF ", "GDEF", "GPOS", "GSUB", "OS/2", "VORG",
"cmap", "head", "hhea", "hmtx", "maxp", "name", "post", "vhea",
"vmtx"]`. Note `CFF ` (CFF outlines), no `glyf`.

### Affected donors (essenfont manifest)

| Donor | Plane 1 cps | In output | Loss |
|---|---|---|---|
| **noto-serif-tangut** (OTF/CFF) | 6916 | **0** | **100%** ← full regression |
| noto-sans (TTF) | 88 | 84 | 4 cps |
| noto-sans-sharada (TTF) | 96 | 95 | 1 cp |
| noto-sans-math (TTF) | 1228 | 1200 | 28 cps |
| noto-music (TTF) | 549 | 537 | 12 cps |
| noto-sans-symbols-2 (TTF) | 1608 | 1596 | 12 cps |
| lentariso (TTF) | 1934 | 1930 | 4 cps |
| egyptian-text (TTF) | 1131 | 1118 | 13 cps |
| uni-hieroglyphica (TTF) | 5108 | 5095 | 13 cps |
| new-gardiner (TTF) | 4537 | 4524 | 13 cps |

**Total: 6,916 Tangut cps + ~100 cps across 9 TTF donors = ~7,000 cps lost.**

### Suggested cause

The `b3e52af` commit ("stitcher: O(1) per-glyph extraction instead
of O(n) full-donor conversion") likely changed the per-glyph
extraction path to assume `glyf` outlines. For OTF/CFF sources,
extraction silently fails and the cp is dropped from the output cmap.

The smaller losses (~1-3% per TTF donor) may be a separate issue —
perhaps an off-by-one or boundary condition in the new
extraction loop. Worth grepping the new spec files for boundary
test cases.

### Net impact on essenfont

- Before fix (0.4.0): 181,354 cmap entries, 59.69% Unicode 17 coverage
- After fix (feature/stitcher-perf): 174,599 entries, 57.47% coverage
- **Net change: −6,755 entries, −2.22 percentage points**

The fix trades Lentariso + Kedebideri coverage (94 cps regained) for
Noto Serif Tangut coverage (6,916 cps lost). Net negative.

### Recommended next step

The Stitcher's per-glyph extraction needs to handle:
- TTF / `glyf` sources (current path)
- OTF / `CFF ` sources (currently broken — likely the regression)
- CBDT/CBLC sources (works in 0.4.0+ for single-source passthrough)

All three glyph-storage modes should round-trip identically. A
parametric spec covering each mode for the same test codepoint
would prevent this class of regression.