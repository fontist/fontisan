# 23 — Boundary type checks (padding, base_record)

## Priority
P3

## Problem
4 `respond_to?` calls in `utilities/padding.rb` and `binary/base_record.rb`
are at String/IO system boundaries. They're the last remaining
"legitimate" duck-typing sites, but the rule is absolute: no
respond_to?.

## Sites
- `padding.rb:30/:55` `size.respond_to?(:bytesize) ? size.bytesize : size`
  — accepts both String (uses bytesize) and Integer (uses self)
- `base_record.rb:27` `io.respond_to?(:empty?) && io.empty?` — String check
- `base_record.rb:37` `io.respond_to?(:rewind)` — IO check (String has no rewind)

## Approach

### padding.rb
- Change the signature: accept Integer only. Callers that have a
  String compute `.bytesize` before calling.

### base_record.rb
- Convert String input to StringIO at the boundary (in `self.read`).
  After conversion, `io` is always a StringIO/IO and responds to
  `rewind`/`empty?` natively. Drop the respond_to? guards.

## Acceptance criteria
- 0 `respond_to?` in `lib/fontisan/utilities/` and `lib/fontisan/binary/`
- All padding and base_record specs pass
