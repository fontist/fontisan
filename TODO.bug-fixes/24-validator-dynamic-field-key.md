# 24 — Validator dynamic field_key

## Priority
P3

## Problem
`lib/fontisan/validators/validator.rb:294` uses `table.respond_to?(field_key)`
to dynamically check whether a table has a named field. This is a
meta-programming pattern for running field-by-field validation rules.

## Site
- :294 `value = if table.respond_to?(field_key)`

## Approach
Replace the dynamic field lookup with BinData's `snapshot` hash.
BinData records expose all declared fields via `snapshot`, which
returns a hash of field name → value. Use `snapshot.key?(field_key)`
instead of `respond_to?`.

Alternatively, declare a typed `FieldValueAccessor` on each table
model that exposes declared fields as a hash.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/validators/validator.rb`
- All validator specs pass
