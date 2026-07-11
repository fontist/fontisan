# 03 — Variation subsetter placeholders

## Priority
P1

## Problem
`Variation::Subsetter` (lib/fontisan/variation/subsetter.rb) has 8
methods that only record "not yet implemented" notes instead of
actually subsetting:

- `subset_gvar_table`
- `subset_cff2_table`
- `subset_metrics_table` (HVAR/VVAR)
- `update_glyph_tables`
- `subset_fvar_table`
- `subset_gvar_axes`
- `subset_cff2_axes`
- `subset_metrics_table_axes`
- `simplify_metrics_regions`

Variable font subsetting via the Variation API is non-functional.

## Goal
Either implement each method or delegate to existing working code
paths (e.g. `Subset::TableStrategy::Cff2` for CFF2 subsetting).

## Approach
The cleanest approach: delegate to the existing `Subset::TableStrategy`
infrastructure where possible, since those strategies already work.

For axis pruning (fvar, gvar axes, metrics axes): filter the
ItemVariationStore regions and tuple counts.

For glyph filtering in variable context: use the same GlyphMapping
approach as the general subsetter.

## Acceptance criteria
- gvar subsetting retains variation data only for kept glyphs
- CFF2 subsetting delegates to Subset::TableStrategy::Cff2
- HVAR/VVAR subsetting filters delta set indices
- fvar axis pruning removes dropped axes from instances
- Region simplification merges duplicate regions
