# 11 — kern groups.plist support

## Priority
P2

## Problem

`Ufo::Compile::FeatureWriters::Kern` (`lib/fontisan/ufo/compile/feature_writers/kern.rb:18`) reads kerning pairs from `kerning.plist` but only partially supports `groups.plist`:

```
# groups.plist data (TODO: groups.plist support is partial).
```

UFO sources that use class-based kerning (kerning classes defined in `groups.plist` instead of per-glyph) lose the class data. Compiled fonts have incomplete kern tables.

## Goal

`Kern` feature writer reads `groups.plist` class definitions, resolves them in `kerning.plist` lookups, and emits GPOS class-based PairPos records (format 2).

## Approach

Two pieces:

1. **Group resolution** — when `kerning.plist` references a group name (rather than a glyph name), expand to all group members. Track group → glyph-set mapping.

2. **Format-2 emission** — emit PairPos format 2 (class-based) when > N pairs share a class. Threshold: ~5 pairs (configurable). Below threshold, fall back to format 1 (pair-based) for size.

Add a `KerningClassResolver` collaborator under `lib/fontisan/ufo/compile/feature_writers/kern/class_resolver.rb`. Stateless given (kerning.plist, groups.plist); returns a list of resolved pairs (glyph_a, glyph_b, value).

## Out of scope

- Variable-font kerning (HVAR table) — separate concern.
- Contextual kerning (`kern` feature with context) — separate feature.

## Effort

~4 hours.

## Dependencies

None.

## Acceptance criteria

- Spec covers:
  - Class-based kerning (groups.plist with two classes, kerning.plist with one pair between them).
  - Mixed class + glyph kerning (one glyph + one class).
  - Threshold: < 5 pairs → format 1; >= 5 pairs → format 2.
- Round-trip: UFO with class kerning → TTF → re-read → GPOS contains the right PairPos records.
