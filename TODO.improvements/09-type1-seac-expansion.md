# 09 — Type 1 seac expansion

## Priority
P2

## Problem

`Type1::CharStringConverter` (`lib/fontisan/type1/charstring_converter.rb:161`) and `Type1::TtfToType1Converter` (`lib/fontisan/type1/ttf_to_type1_converter.rb:256`) emit seac operators as-is when converting Type 1 → TrueType. seac (Standard Encoding Accented Character) composites two glyphs into one — e.g., é = e + acute at a fixed offset. Modern renderers deprecated seac; Type 1 → TTF conversion must expand it into actual outlines.

## Goal

`TtfToType1Converter` (and the reverse path) expands seac into merged outlines:

1. Resolve the two referenced glyphs (base + accent) via the source font.
2. Translate them to the seac offset.
3. Concatenate their contours into the parent glyph.

## Approach

Add a `SeacExpander` collaborator under `lib/fontisan/type1/seac_expander.rb` that takes:

- A charstring with a seac operator
- A resolver: glyph_name → charstring (for the base + accent)

Returns a new charstring with the seac replaced by the merged outline operators.

Walk the source's standard-encoding lookup (Adobe Standard Encoding) to map seac's two uint8 operands to glyph names. Decode the operands:

```
seac: asb base accent
  asb     — sidebearing (unused in expansion)
  base    — Adobe Standard Encoding index of the base glyph
  accent  — Adobe Standard Encoding index of the accent glyph
```

The expander recursively expands seac in base/accent glyphs (seac can nest).

## Out of scope

- seac in CFF (not Type 1) — CFF deprecated seac entirely; should be a warning, not an expansion.
- Replacing the deprecated `seac` operator in TTF → Type 1 conversion — seac emission is already removed; we only need to handle source seac on input.

## Effort

~6 hours.

## Dependencies

None.

## Acceptance criteria

- Spec covers:
  - Single-level seac (e.g., é) → expanded to merged outline.
  - Nested seac (e.g., a glyph that references another seac glyph as its base) → fully expanded.
  - seac referencing a missing glyph → raise `SeacReferenceError` with the missing name.
- Round-trip: Type 1 with seac → TTF → re-read → outline matches the merged shape.
