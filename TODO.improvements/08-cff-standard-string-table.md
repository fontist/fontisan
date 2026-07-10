# 08 — CFF standard string table

## Priority
P2

## Problem

`Tables::Cff` (`lib/fontisan/tables/cff.rb:419`) ships only a partial standard string table (the 391 predefined Type 1 / CFF strings per spec appendix A). Glyph names that should be in the standard set are duplicated in the custom strings index, wasting space and breaking round-trip fidelity with fontTools.

## Goal

Complete the 391-string standard table per CFF spec. `Cff` parses glyph names against the standard table; only non-standard names go in the custom strings index.

## Approach

Replace the partial list with the canonical 391 strings (spec appendix A, also in fontTools' `fontTools.cffLib.strings`).

Add a class method:

```ruby
class Cff < Binary::BaseRecord
  STANDARD_STRINGS = [...].freeze  # 391 entries

  def self.standard_string?(name)
    STANDARD_STRINGS.include?(name)
  end

  def self.standard_string_index(name)
    STANDARD_STRINGS.index(name)
  end
end
```

Update the CFF builder (TODO 05's `CffBuilder`) to skip custom-string encoding when a name is standard.

## Out of scope

- CID-keyed fonts (no name strings) — unaffected.
- Custom charstring-internal names (operator names) — those are operators, not string IDs.

## Effort

~2 hours.

## Dependencies

- TODO 05 (OTF compiler real CFF) benefits; doesn't strictly block.

## Acceptance criteria

- Spec covers: every standard name → correct index, every non-standard name → custom index.
- Round-trip: CFF with mixed standard/non-standard names → read → emit → identical bytes.
