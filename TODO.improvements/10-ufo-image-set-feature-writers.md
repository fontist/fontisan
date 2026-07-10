# 10 — UFO image set + feature writers

## Priority
P2

## Problem

Two UFO subsystems ship as stubs:

- `Ufo::ImageSet` (`lib/fontisan/ufo/image_set.rb:6`) — placeholder, "real implementation lands with TODO 02 (glyph model + images)"
- `Ufo::Features` (`lib/fontisan/ufo/features.rb:8`) — placeholder, "TODO 08 (feature writers)"

UFO sources with `features.fea` (OpenType layout compilation from text) or images (UFO 3 image data) lose both on round-trip.

## Goal

### ImageSet
- `Ufo::ImageSet` parses UFO 3 image data: reads `images/` directory, exposes `images` array of `Ufo::Image` records with filename + sha + PNG bytes.
- `Ufo::Glyph#image` (already modeled) reads image references; round-trips.
- Compile: glyphs with image references emit `CBDT`/`CBLC` color-bitmap entries (reusing the BinData models from PR #106).

### Features (feature writers)
- `Ufo::Features` parses `features.fea` via a new `FeatureCompiler` collaborator.
- Compiles OpenType layout rules (kern, liga, calt, etc.) into `GSUB`/`GPOS` tables.
- Output tables are mergeable into the compiled font.

## Approach

### ImageSet
Reuse existing `Tables::Cbdt`/`Cblc` BinData records. Convert each UFO image to a small-metrics-format PNG block. Build CBLC IndexSubTableArray pointing at each block.

For test fixtures: the existing `CbdtFixture` (PR #107) already builds valid CBDT/CBLC pairs — use as reference for the emission shape.

### Features
Use a fea-syntax parser. Options:
- **Inline parser** — non-trivial; ~5 days work, ~500 LOC.
- **Adapter for `fontTools.feaLib`** — only available with Python; introduces cross-language dep (violates "pure Ruby" rule).
- **Limited fea subset** — handle only kern/liga (most common); error on unsupported constructs.

Recommendation: **limited fea subset** initially, expanding as real-world fonts demand.

Add `FeatureCompiler` under `lib/fontisan/ufo/compile/feature_compiler.rb`. Parses `features.fea` into a tree, then emits GSUB/GPOS records. Starts with:
- `feature kern { pair ... } kern;` → GPOS PairPos (format 1)
- `feature liga { sub ... by ...; } liga;` → GSUB LigatureSubst

## Out of scope

- Adobe FEA parser completeness — full spec is 100+ pages; cover what real fonts use.
- AFDKO integration — out of scope.

## Effort

- ImageSet: ~1 day (BinData + IO).
- Features (limited subset): ~3 days (kern + liga paths).
- Features (full fea): weeks — explicitly out of scope.

## Dependencies

- TODO 05 (OTF compiler real CFF) — image glyphs end up in CBDT, unrelated to CFF. No dep.
- None blocking.

## Acceptance criteria

### ImageSet
- Spec covers read of UFO with one image → `glyph.image` populated, `imageset.images.first.bytes` matches PNG bytes.
- Compile round-trip: UFO with image glyph → TTF → re-read → CBDT/CBLC tables present, bitmap decodable.

### Features
- Spec covers a UFO with kern feature → GPOS table present with correct PairPos.
- Spec covers a UFO with liga feature → GSUB table present with correct LigatureSubst.
- Unsupported fea constructs raise `UnsupportedFeaError` with a clear message.
