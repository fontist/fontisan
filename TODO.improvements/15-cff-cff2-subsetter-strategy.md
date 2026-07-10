# 15 — CFF/CFF2 subsetter strategy

## Priority
P0

## Problem

The subsetter's `TableStrategy::REGISTRY` has entries for glyf/loca (TrueType outlines) but NOT for CFF or CFF2 (PostScript outlines). Both fall through to `PassThroughStrategy`, which copies the full source table verbatim.

Two concrete failure modes:

1. **Profiles drop CFF entirely.** The `web`, `pdf`, and `minimal` profiles list glyf/loca but not CFF/CFF2. A CFF-based OTF font subsetted to any of these profiles loses ALL outlines — the output has `cmap`/`head`/`hmtx`/`maxp` but no CFF. The font has no glyph data.

2. **`full` profile includes CFF but doesn't subset it.** The full CFF table is copied verbatim while `maxp.numGlyphs` is updated to the subset count. The CFF CharStrings INDEX has the original glyph count; `maxp` says fewer. Invalid mismatch — fontTools and Chrome reject.

This affects every CFF-based OpenType font (the majority of professional fonts — Adobe, Google Fonts OTFs, variable CFF2 fonts).

## Goal

Two new strategy classes:
- `Subset::TableStrategy::Cff` — subsets CFF v1 tables
- `Subset::TableStrategy::Cff2` — subsets CFF2 tables (variable-font aware)

Both registered in the REGISTRY. The `web` and `pdf` profiles updated to include CFF/CFF2 (conditionally — only when the source font has them; the profile loader already handles this via "if table present").

## Approach

Each strategy:

1. Parses the CFF/CFF2 table via `Tables::Cff`/`Tables::Cff2` BinData models.
2. Filters the CharStrings INDEX to only the subset's glyph IDs.
3. Rebuilds the INDEX with retained charstrings in subset order.
4. Updates the charset (GID → SID mapping) to match the new GID ordering.
5. Prunes unused GlobalSubrs + PrivateSubrs (subroutines referenced only by dropped charstrings).
6. Rewrites the Top DICT offsets to match the new INDEX positions.

For CFF2, additionally:
7. Filters FDSelect (per-glyph FD index) to the subset GIDs.
8. Preserves the ItemVariationStore intact (it applies to all glyphs, not per-glyph).
9. Preserves vsindex/blend operators in charstrings (they reference ItemVariationStore regions, not per-glyph data).

fontisan already has the CFF/CFF2 BinData models for reading. The strategy adds write/filter capability.

## Out of scope

- CFF2 blend/vsindex ENCODING (TODO 06) — that's about generating new CFF2 from scratch, not subsetting existing CFF2.
- OTF compiler real CFF (TODO 05) — that's about building CFF from UFO outlines.
- Font-level outline conversion (TTF→OTF) — that's `Converters::OutlineConverter`.

## Effort

~1-2 days for CFF v1 (well-understood algorithm).
~1 additional day for CFF2 (adds FDSelect + ItemVariationStore handling).

## Dependencies

None. The CFF/CFF2 BinData models already exist.

## Acceptance criteria

- A CFF-based OTF font subsetted to the `web` profile produces valid output (fontTools accepts it, Chrome OTS doesn't reject).
- The subset CFF table has exactly `subset_glyph_count` charstrings (not the source's full count).
- Subroutines referenced only by dropped glyphs are pruned.
- CFF2 variable fonts retain their ItemVariationStore and variation deltas after subsetting.
- New spec covers: CFF font → web subset → fontTools decode → glyph count matches.
- Profile YAML updated: `web` and `pdf` profiles include CFF/CFF2 conditionally.
