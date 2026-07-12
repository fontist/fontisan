# 11 — Remaining respond_to? violations

## Priority
P2

## Problem
8 `respond_to?` duck-typing calls remain in lib/fontisan/ after
bug-fix #08 only fixed 2 of 10 instances.

## Remaining sites
- woff2_font.rb (2) — respond_to?(:table_data)
- outline_extractor.rb (2) — respond_to?(:table), respond_to?(:empty?)
- sfnt_font.rb (1) — respond_to?(:length) on BinData array (always true)
- woff_font.rb (1) — respond_to?(:length) on BinData array (always true)
- glyph_accessor.rb (3) — respond_to?(:table), respond_to?(:compound?),
  respond_to?(:components)
- svg/font_generator.rb (1) — respond_to?(:table)

## Approach
- Remove always-true checks (BinData arrays always have .length)
- Replace font type checks with is_a?(SfntFont) / is_a?(Woff2Font)
- Replace glyph type checks with is_a? on glyf record type

## Acceptance criteria
- 0 respond_to? in lib/fontisan/ (excluding respond_to_missing?)
