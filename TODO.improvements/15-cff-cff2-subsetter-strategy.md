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

**Architecturally preferred path (TODO #05 + #10b dependency):**

If the CFF → UFO conversion (`Ufo::Convert::FromBinData#extract_cff_glyphs`, currently stubbed as TODO #10b) is fully implemented, AND the OTF compiler emits real CFF charstrings (TODO #05), then CFF subsetting is trivial:

```
CFF font → Ufo::Convert::FromBinData → UFO (with contours)
         → drop glyphs not in mapping
         → Ufo::Compile::OtfCompiler → new CFF
```

No standalone INDEX rebuilder needed. The UFO model is the canonical representation; CFF is a serialization. This is DRY, MECE, OCP-compliant.

**Fallback path (standalone CFF INDEX rebuilder):**

If TODO #05 + #10b are not yet done, a standalone strategy can work at the binary level:

1. Parse CFF header → Name INDEX → Top DICT INDEX → String INDEX → Global Subr INDEX
2. Decode Top DICT operators → get charset offset, CharStrings offset, Private offset
3. Parse CharStrings INDEX → get byte range per charstring
4. Filter to subset GIDs
5. Rebuild CharStrings INDEX with retained charstrings
6. Rebuild charset to match new GID ordering
7. Optionally prune GlobalSubrs/PrivateSubrs
8. Recompute all offsets in Top DICT
9. Reassemble CFF bytes

This is more work than the UFO round-trip path and duplicates logic the compile pipeline already has. Prefer the UFO path.

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
