# 08 — respond_to? duck typing violations

## Priority
P1

## Problem
10 `respond_to?` calls use duck typing where proper type checks or
architecture redesigns would be more correct and safer.

## Specific violations
- `woff2_font.rb:188,198` — `respond_to?(:table_data)` on underlying font
- `outline_extractor.rb:44` — `respond_to?(:table)` on font
- `outline_extractor.rb:133` — `respond_to?(:empty?)` on glyph
- `woff_font.rb:362` — `respond_to?(:length)` on table_entries
- `sfnt_font.rb:358` — `respond_to?(:length)` on tables array
- `glyph_accessor.rb:58,356,359,387` — multiple respond_to? on glyph/font

## Approach
- Replace `respond_to?(:table)` with `is_a?(SfntFont)` type checks
- Replace `respond_to?(:table_data)` with proper type checks
- For BinData records that always have `.length`, remove the check entirely
- For glyph compound check, use `is_a?` on the glyf record type

## Acceptance criteria
- 0 `respond_to?` in lib/fontisan/ (excluding spec/)
