# 06 — CFF2 blend/vsindex operators

## Priority
P2

## Problem

`Ufo::Compile::VariableOtf` (`lib/fontisan/ufo/compile/variable_otf.rb:12`) emits static CFF2 only:

```
- CFF2 outlines (static — blend/vsindex operators are TODO 07/18)
TODO 07 (blend/vsindex) and TODO 18 (blend integration) to be
```

Variable CFF2 fonts (e.g., variable OTF output from a UFO with `fvar` + `gvar`-equivalent masters) can't round-trip. The compiled font is static — variation deltas are dropped.

## Goal

`VariableOtf` emits CFF2 with `blend` and `vsindex` operators per CFF2 spec section 3.A.4. A variable UFO source compiles to a variable OTF that renders correctly at any chosen instance along each axis.

## Approach

Two pieces:

1. **CharString encoder** — extend the Type 2 charstring builder (from TODO 05) to emit `blend` after each variation-aware value. The master value is the default; deltas for each region are pushed on the stack then summed via `blend`.

2. **ItemVariationData emission** — translate the UFO master model (`gvar`-equivalent: per-glyph deltas keyed by region) into CFF2's `ItemVariationData` and `ItemVariationStore` structures. Reuse `Ufo::Compile::ItemVariationStore` which already handles this for the variable-TTF path.

3. **Region detection** — pre-pass over `fvar` axes + master locations to compute the set of variation regions. Same algorithm as `Ufo::Compile::Fvar`.

## Out of scope

- HVAR/VVAR/MVAR tables for variable OTF — those are outside CFF2 but already partially supported; track separately if needed.
- Backwards-compat with non-variable CFF fonts — separate concern.
- Subroutine packing of variation-aware charstrings — TODO follow-up.

## Effort

~3-5 days. CFF2 charstring semantics are intricate.

## Dependencies

- TODO 05 (OTF compiler real CFF) — must land first; the CFF2 builder extends the CFF builder.

## Acceptance criteria

- New spec covers:
  - Single-axis variable font → CFF2 with correct `blend` operators + `ItemVariationStore`
  - Multi-axis variable font → region table correct, no cross-axis contamination
  - Instance generation via `Variation::InstanceGenerator` produces output identical to direct master compile (within tolerance)
- Round-trip: UFO with fvar + masters → variable OTF → re-read → `fvar` axes match, instances render correctly.
