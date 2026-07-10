# 01 — CBDT/CBLC GID-stable propagation

## Priority
P0

## Problem

`Stitcher::CbdtPropagator#propagate_tables_into` (`lib/fontisan/stitcher/cbdt_propagator.rb:147`) copies CBDT/CBLC bytes raw from the CBDT source into the compiled font. CBLC indexes glyphs by **source GID**. But the Stitcher's compile order is:

1. `inject_notdef`      → compiled GID 0
2. `copy_outlines`      → compiled GIDs 1..N (outline donor glyphs)
3. `add_placeholder_glyphs` → compiled GIDs N+1..M (CBDT placeholders, often renamed to `"gid{N}.1"` to avoid name collisions per PR #108)

So the CBDT source's GID 110 may end up at compiled GID 4027+ — but the raw-bytes CBLC still says "GID 110 → bitmap for source GID 110". The bitmap data dangles, pointing at whatever outline glyph happens to be at compiled GID 110.

This is masked in the cited Essenfont use case because FSung-3 (Ext G outlines) and NotoColorEmoji (emoji bitmaps) cover disjoint codepoint ranges. But for any stitch where CBDT and outline donors cover overlapping codepoint ranges (e.g. assembling a combined Latin+emoji font from a single source that has both glyf and CBDT), the bitmap-to-glyph mapping is wrong.

Documented as a known limitation in `docs/STITCHER_GUIDE.adoc` (added in PR #110).

## Goal

After compile, `propagate_tables_into` rebuilds the CBLC by:
1. Walking the compiled font's cmap to find each compiled GID for every CBDT-covered codepoint.
2. Mapping source GID → compiled GID via the Stitcher's `GlyphMapping`.
3. Building a new CBLC whose `BitmapSize.startGlyphIndex`/`endGlyphIndex` and IndexSubTableArray entries reference compiled GIDs.
4. Building a new CBDT that lays out bitmap blocks in compiled-GID order so each block matches its CBLC offset.

The result: any stitch — overlapping codepoint ranges or not — produces a font where CBLC's GID references line up with the compiled GIDs that actually have the right bitmaps.

## Approach

Reuse the CBDT/CBLC BinData models from PR #106:
- `Tables::Cblc`, `Tables::CblcBitmapSize`, `Tables::CblcIndexSubTableArrayEntry`, `Tables::CblcIndexSubTable`
- `Subset::TableStrategy::ColorBitmapSubsetter` and its plan classes — already do the offset-remap math for the subsetter; same algorithm shape, different mapping source

New collaborator: `Stitcher::CbdtReindexer`. Sits between compile and table propagation:

```
compile TTF
  ↓
CbdtReindexer.reindex(source_cblc, source_cbdt, glyph_mapping) → new (CBLC, CBDT) bytes
  ↓
FontWriter.write_to_file(tables.merge("CBLC" => new_cblc, "CBDT" => new_cbdt))
```

The reindexer is stateless given inputs — testable in isolation.

Update `propagate_tables_into` to call the reindexer instead of raw-bytes copy.

Update `docs/STITCHER_GUIDE.adoc` to remove the "known limitation" note.

## Out of scope

- Handling IndexSubTable format 4 (bit-packed offsets) — already unsupported in the subsetter; same gap.
- Multi-strike CBLC where each strike has a different glyph range — covered (reindexer iterates strikes).
- Subsetting the source CBDT before stitching — separate concern (the subsetter already does this for `Subset::Builder`).

## Effort

~1 day.

## Dependencies

None. Unblocks TODO 02.

## Acceptance criteria

- New spec `spec/fontisan/stitcher/cbdt_reindexer_spec.rb` covers:
  - Disjoint-range stitch: CBLC's compiled GID references line up.
  - Overlapping-range stitch: CBDT placeholder at compiled GID N gets the bitmap originally at source GID M (mapping via GlyphMapping).
  - Multi-strike CBLC: every strike's bitmap data lands at the right compiled GID.
- Existing `spec/fontisan/stitcher/outline_priority_spec.rb` collection-mode test (currently skipped) is unblocked and passes.
- The "GID-stability limitation" section in `docs/STITCHER_GUIDE.adoc` is removed.
