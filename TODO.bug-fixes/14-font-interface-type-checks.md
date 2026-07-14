# 14 — Font interface type checks

## Priority
P1

## Problem
~30 `respond_to?` calls probe whether an object is font-like by
checking for `:table`, `:tables`, `:table_data`, `:has_table?`,
`:header`, `:cff?`. The codebase has a typed font hierarchy
(`SfntFont`, `TrueTypeFont`, `OpenTypeFont`, `WoffFont`, `Woff2Font`,
`Type1Font`) — these should be checked with `is_a?`.

## Sites (by category)

### Collection builders
- `collection/builder.rb:61` `respond_to?(:table_data)`
- `collection/dfont_builder.rb:47` `respond_to?(:table_data)`

### Subset
- `subset/builder.rb:115` `respond_to?(:table)`
- `subset/table_strategy/cff2.rb` — already cleaned

### Converters
- `converters/woff2_encoder.rb:221` `respond_to?(:table_names)`
- `converters/woff2_encoder.rb:250` `respond_to?(:has_table?)`
- `converters/woff2_encoder.rb:313/:315/:317` font shape probes
- `converters/outline_converter.rb:278/:282` `respond_to?(:tables)` / `:table`
- `converters/table_copier.rb:33/:37/:76/:80` font shape probes
- `converters/woff_writer.rb:116/:305` font shape / `:cff?`
- `converters/type1_converter.rb:115/:160/:222/:723-749` font shape + font_info probes
- `converters/format_converter.rb:415` `respond_to?(:table)`

### Stitcher
- `stitcher/source.rb:83` `respond_to?(:has_table?)`
- `stitcher/source.rb:193/:220/:228` table parse probes
- `stitcher/source.rb:287/:289/:375/:377` glyph type probes (see TODO 15)

### Variable
- `variable/delta_aplicator.rb:263` `respond_to?(:table_data)`
- `variable/static_font_builder.rb:80` `respond_to?(:tables)`
- `variation/variation_preserver.rb:151/:152` `respond_to?(:has_table?)` / `:table_data`

### Commands
- `commands/validate_command.rb:216` `respond_to?(:table)`
- `commands/pack_command.rb:177/:188` `respond_to?(:header)`

### Validation
- `validation/collection_validator.rb:249/:259` `respond_to?(:has_table?)`

### Woff2 table transformer
- `woff2/table_transformer.rb:153` `respond_to?(:table_data)`

### Other
- `commands/unpack_command.rb:210` `respond_to?(:table)`

## Approach
1. Define `SfntFont` as the type for any TrueType/OpenType/WOFF/WOFF2
   font (already the base class).
2. Define `Type1Font` similarly (already exists).
3. Replace `respond_to?(:table)` / `:tables` / `:table_data` / `:has_table?`
   with `is_a?(SfntFont)` (or `is_a?(Type1Font)` where applicable).
4. Where the input legitimately can be either SfntFont or Type1Font,
   accept a union: `font.is_a?(SfntFont) || font.is_a?(Type1Font)`.
5. For `respond_to?(:header)` in pack_command, the SfntFont exposes
   `sfnt_version` directly (already used elsewhere).
6. For converters/type1_converter.rb font_info probes, the `font_info`
   is always a `Type1::FontInfo` record — replace with `is_a?`.

## Affected specs
- spec/fontisan/collection/builder_spec.rb (uses doubles)
- spec/fontisan/subset/builder_spec.rb (uses doubles)
- spec/fontisan/converters/* (most use real fonts; check each)
- spec/fontisan/stitcher/* (check)

The collection/builder_spec and subset/builder_spec were identified in
PR #135 as using doubles that block the is_a?(SfntFont) migration.
Migrate them to real SfntFont instances or SimpleDelegator-based fakes.

## Acceptance criteria
- 0 `respond_to?(:table)` / `:tables` / `:table_data` / `:has_table?` /
  `:header` / `:cff?` in `lib/fontisan/`
- All affected specs pass with real fonts or SimpleDelegator-based fakes
