# 15 — Glyph type checks + SimpleGlyph#points bug

## Priority
P0

## Problem
~15 `respond_to?` calls probe glyph shape (`:simple?`, `:compound?`,
`:points`, `:bounding_box`). Plus the latent bug discovered in PR #135:
`Type1::TTFToType1Converter#extract_points` calls `glyph.points.each`
but `Tables::SimpleGlyph` has no `points` method. The `respond_to?`
check silently masked this for years.

## Sites
- `type1/ttf_to_type1_converter.rb:140` `respond_to?(:points)` — masks bug
- `type1/pfa_generator.rb:307` `respond_to?(:points)` — same bug
- `type1/pfb_generator.rb:276` `respond_to?(:points)` — same bug
- `ufo/convert/from_bin_data.rb:192/:312/:323/:325` `respond_to?(:simple?)` / `:compound?`
- `ufo/convert/from_bin_data.rb:361` `respond_to?(:glyph_name)`
- `stitcher/source.rb:287/:289/:375/:377` `respond_to?(:simple?)` / `:compound?`
- `hints/truetype_hint_extractor.rb:66` `respond_to?(:instructions)`
- `tables/glyf.rb:243` already fixed in PR #135

## SimpleGlyph API surface (current)
- `num_contours`, `num_points`
- `points_for_contour(index)` → Array<Hash{x,y,on_curve}>
- `point_at(index)`, `on_curve?(index)`
- `bounding_box` → [x_min, y_min, x_max, y_max]
- `simple?`, `compound?`, `empty?`

## Approach
1. Add `Tables::SimpleGlyph#points` — returns a flat Array<Hash> across
   all contours. Single source of truth, lazy-built.
2. Add `Tables::CompoundGlyph#points` — returns the union of component
   points (or empty if no components).
3. Replace all `respond_to?(:points)` with `is_a?(Tables::SimpleGlyph)`.
4. Replace `respond_to?(:simple?)` / `:compound?` with `is_a?` against
   `Tables::SimpleGlyph`, `Tables::CompoundGlyph`, `Tables::Cff::CFFGlyph`.
5. For `:bounding_box`, the typed glyph classes all have it — drop the
   check.
6. For `:glyph_name` on Post glyph records, declare it as a method (or
   always-present BinData field).
7. For `:instructions` on SimpleGlyph, declare it.

## Acceptance criteria
- 0 `respond_to?(:simple?)` / `:compound?` / `:points` / `:bounding_box` /
  `:glyph_name` / `:instructions` in `lib/fontisan/`
- Type 1 conversion now produces non-empty CharString data for simple
  glyphs (the previously-broken `extract_points` path)
- All Type 1 specs pass
