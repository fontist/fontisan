# 04 — UFO composite glyph encoding

## Priority
P1

## Problem

`Ufo::Compile::GlyfLoca` (`lib/fontisan/ufo/compile/glyf_loca.rb:137`) emits simple glyphs only. UFO sources with composite glyphs (e.g., é defined as a component reference to e + acute) lose their component structure on compile — the compiled glyf either drops them or depends on `flatten_components` filter pre-processing.

## Goal

`GlyfLoca` encodes composite glyphs natively per OpenType spec section 5.6. A UFO `<component>` element maps to a glyf component record referencing the target glyph by index, preserving the original transform.

## Approach

Add a `CompositeEncoder` collaborator in `lib/fontisan/ufo/compile/glyf_loca/composite_encoder.rb` that takes a UFO `<component>` plus a GID-resolver (component name → compiled GID) and emits the binary component record per OT spec:

```
uint16 flags
uint16 glyphIndex
(uint8|uint8|uint8|uint8 | int8|int8|int8|int8 | uint8) args  # depends on flags bits 0/1
(F2Dot14 × 4 | F2Dot14 × 2 | F2Dot14) transformation  # depends on flags bits 7/6/3
```

`GlyfLoca` invokes the encoder when a UFO glyph has components (no contours, OR contours + components — latter is rare but spec-legal).

The existing `flatten_components` filter remains for callers who want pre-flattening (e.g., for fonts that target renderers without component support).

## Out of scope

- Variable-font composite variation deltas (`gvar`) — separate concern, TODO 06's blast radius.
- Cycling component references (A → B → A) — these need pre-validation, tracked separately.

## Effort

~1 day.

## Dependencies

None.

## Acceptance criteria

- New spec covers encoding of all 8 component arg/transform combinations (flags bit patterns).
- Round-trip spec: UFO with composite → compile → re-read via `FontLoader` → components match original.
- The `flatten_components` filter still works as a pre-pass for callers that want flattened output.
