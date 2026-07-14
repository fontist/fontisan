# 26 — Variation preserver spec migration

## Priority
P3

## Problem
`lib/fontisan/variation/variation_preserver.rb:153` still uses
`respond_to?(:has_table?) && respond_to?(:table_data)` because the
spec uses `instance_double(TrueTypeFont)` with extensive per-test
stubs. Replacing with `is_a?(SfntSource)` requires migrating the
spec to use `SpecHelpers::FakeFont`.

## Site
- `variation_preserver.rb:151-154` (with TODO comment)
- `spec/fontisan/variation/variation_preserver_spec.rb` (entire file)

## Approach
1. Update spec to use `SpecHelpers::FakeFont` instead of `instance_double`.
2. For per-test variations, mutate `font.tables_hash` instead of
   stubbing `has_table?`/`table_data`.
3. Replace `respond_to?` check in production with `is_a?(SfntSource)`.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/variation/variation_preserver.rb`
- All variation_preserver specs pass
