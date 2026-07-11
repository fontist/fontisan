# 04 — UFO image compile round-trip

## Priority
P1

## Problem
TODO.improvements #10 acceptance criteria says:
"Compile round-trip: UFO with image glyph → TTF → re-read → CBDT/CBLC
tables present, bitmap decodable."

We implemented `ImageSet` read/write but the compile path (UFO image
references → CBDT/CBLC binary tables) was not implemented. UFO glyphs
with `<image>` references lose their images on compile to TTF/OTF.

## Goal
During UFO → TTF/OTF compilation, glyphs with image references emit
CBDT/CBLC entries reusing the existing BinData models.

## Approach
- Extend `Compile::CbdtCblc` (or add a new builder method) that takes
  the UFO ImageSet and produces CBDT/CBLC bytes
- Wire into `TtfCompiler` and `OtfCompiler` when the UFO has an image set
- Each image becomes a small-metrics-format PNG block
- CBLC IndexSubTableArray points at each block

## Acceptance criteria
- UFO with one image glyph → TTF → re-read → CBDT/CBLC present
- Bitmap decodable from the output font
