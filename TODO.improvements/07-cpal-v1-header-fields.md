# 07 — CPAL v1 header fields

## Priority
P2

## Problem

`Tables::Cpal` (`lib/fontisan/tables/cpal.rb:106,184`) only parses CPAL v0 fields. CPAL v1 adds:

- `numPaletteEntryLabels` (uint16) — count of palette entry labels
- `numPaletteLabels` (uint16) — count of palette labels
- `paletteEntryLabelsOffset` (uint32) — offset to label records
- `paletteLabelsOffset` (uint32) — offset to label records

These attach human-readable names (via the `name` table) to color palettes and entries. Fonts with CPAL v1 lose this metadata on parse.

## Goal

`Tables::Cpal` parses v1 header fields and exposes:

- `palette_labels` — array of name-record IDs, one per palette
- `palette_entry_labels` — array of name-record IDs, one per palette entry index

Round-trip preserves the labels.

## Approach

Extend the BinData record in `lib/fontisan/tables/cpal.rb`:

```ruby
class Cpal < Binary::BaseRecord
  uint16 :version
  uint16 :num_palette_entries
  uint16 :num_palettes
  uint16 :num_color_records
  uint32 :color_records_offset
  array :color_record_indices, type: :uint16, initial_length: :num_palettes
  # v0 ends here

  # v1 extension — only present when version >= 1
  choice :v1_fields, onlyif: -> { version >= 1 } do
    uint16 :num_palette_entry_labels
    uint16 :num_palette_labels
    uint32 :palette_entry_labels_offset
    uint32 :palette_labels_offset
  end
end
```

After BinData parse, lazily walk the label offsets to populate `palette_labels` and `palette_entry_labels` arrays.

For emission: if v1 fields are set, include them; else emit v0.

## Out of scope

- CPAL v2 changes (none — v1 is the latest defined).
- Building new palettes from scratch — just parse + emit.

## Effort

~4 hours.

## Dependencies

None.

## Acceptance criteria

- New spec covers parse of a synthetic CPAL v1 table with both label arrays.
- Round-trip: v1 table → read → `to_binary_s` → identical bytes.
- v0 tables still parse and emit unchanged.
