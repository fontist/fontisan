# 12 — `cbdt_fixture.rb` full BinData conversion

## Priority
P3

## Problem

`spec/support/cbdt_fixture.rb` was partially refactored in PR #107 (CBDT/CBLC use the new BinData models), but the remaining tables still hand-roll binary packing:

- `head_table` — 19-element `[...].pack("NNNNnnNNnnnnnnnnnn")`
- `hhea_table` — 16-element pack
- `os2_table` — 43-element pack
- `name_table` — manual record + offset arithmetic
- `post_table` — manual pack
- `hmtx_table` — `Array.new(num_glyphs) { [1000, 0] }.flatten.pack("n*")`
- `cmap_table` / `format4_subtable` / `format12_subtable` — full cmap builder, ~80 lines

~200 lines of pack/unpack that duplicate the layout knowledge in `Tables::*`. If any table layout changes, the fixture breaks silently — the same anti-pattern PR #107 already fixed for CBDT/CBLC.

## Goal

Every table builder in `cbdt_fixture.rb` constructs via BinData record (`Tables::Head`, `Tables::Hhea`, `Tables::Maxp`, `Tables::Os2`, `Tables::Name`, `Tables::Post`, `Tables::Hmtx`, `Tables::Cmap`). No more `[...].pack(...)` calls.

The fixture's self-test (`spec/support/cbdt_fixture_spec.rb`) catches any drift between the fixture's output and the BinData models.

## Approach

For each table, replace the hand-rolled pack with a `Tables::*` BinData construction:

```ruby
# Before
def head_table
  [0x00010000, 0x00005000, ...].pack("NNNNnnNNnnnnnnnnnn")
end

# After
def head_table
  Tables::Head.new(
    version_raw: 0x00010000,
    font_revision: 0x00005000,
    ...
  ).to_binary_s
end
```

For tables with field shapes that don't match the BinData record cleanly (e.g., `name_table`'s variable-length string storage), use the BinData record's nested array attributes.

For `cmap_table`: extract the format-4 / format-12 subtable builders to a reusable `Tables::Cmap.from_mappings(mappings)` class method. The same logic is duplicated in `Subset::TableStrategy::Cmap::Builder` and `Subset::TableStrategy::ColorBitmapSubsetter` — DRY win across three call sites.

## Out of scope

- Refactoring the BinData models themselves — only changes the fixture's consumers.
- Adding `Tables::Cmap.from_mappings` if the DRY extraction scope proves larger than the fixture alone (split into separate PR).

## Effort

~4 hours.

## Dependencies

None.

## Acceptance criteria

- `spec/support/cbdt_fixture.rb` contains zero `[...].pack` calls.
- `spec/support/cbdt_fixture_spec.rb` self-test still passes (it round-trips via the BinData models; the assertions don't change).
- All downstream specs that use `CbdtFixture` still pass.
- Bundle size of the fixture file drops from ~300 lines to ~150.
