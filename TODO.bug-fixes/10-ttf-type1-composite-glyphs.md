# 10 — TTF → Type 1 composite glyph handling

## Priority
P1

## Problem
`Type1::TtfToType1Converter#convert_composite_glyph`
(ttf_to_type1_converter.rb:256) returns an empty charstring for
compound (composite) TrueType glyphs. Fonts with composite glyphs
lose those glyphs entirely during TTF → Type 1 conversion.

## Goal
Decompose composite glyphs into their component outlines (applying
transforms), merge into a single outline, and convert to Type 1
charstring.

## Approach
Reuse the flattening logic from `Stitcher::Source#flatten_compound_into`
which already handles component decomposition with transforms.

## Acceptance criteria
- TTF with composite glyphs → Type 1: composite outlines present
- Spec covers a composite glyph conversion
