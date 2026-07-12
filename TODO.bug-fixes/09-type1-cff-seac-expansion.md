# 09 — Type 1 → CFF seac expansion incomplete

## Priority
P0

## Problem
`Type1::CharStringConverter#expand_seac` (charstring_converter.rb:161)
emits just `endchar` instead of merging base+accent outlines. Type 1
fonts with seac composites lose their accented glyphs when converted
to CFF.

The `SeacExpander` (TODO.improvements #09) handles seac for Type 1 →
TTF, but the Type 1 → CFF path in `CharStringConverter` was never
wired to use it.

## Goal
Use `SeacExpander` to expand seac before converting to CFF, so
accented glyphs survive the Type 1 → CFF conversion.

## Acceptance criteria
- Type 1 font with seac → CFF: accented glyphs present in output
- Spec covers a seac composite conversion
