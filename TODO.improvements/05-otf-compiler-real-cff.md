# 05 — OTF compiler real CFF charstrings

## Priority
P1

## Problem

`Ufo::Compile::OtfCompiler` (`lib/fontisan/ufo/compile/otf_compiler.rb:9`) currently emits a placeholder CFF table — no real charstrings. Any OTF output is incomplete:

```
# TODO.full/10: this currently emits a placeholder CFF table
# real charstrings. Full CFF construction lands when TODO 10
```

The font loads but renders nothing useful. Production OTF output is blocked.

## Goal

`OtfCompiler` emits a complete CFF table with:
- Real Type 2 charstrings for every glyph (converted from UFO contours)
- Valid Top DICT (font matrix, charset, encoding, CharStrings INDEX offset)
- Valid Private DICT (default width, nominal width, SubrZERO subroutines if any)
- Correct name INDEX, charset, FDSelect/FDArray (for CID-keyed fonts)

Round-trip: UFO → compile → re-read via `FontLoader` → contours match.

## Approach

Reuse the Type 2 charstring conversion logic from `lib/fontisan/type1/charstring_converter.rb` — UFO contours → moveto/lineto/curveto closepath is structurally identical to Type 1 → Type 2 charstring conversion.

Add a new `CffBuilder` collaborator under `lib/fontisan/ufo/compile/otf_compiler/cff_builder.rb` that owns:

1. **Top DICT construction** — font matrix, ROS (if CID), charstrings offset.
2. **CharString INDEX** — per-glyph Type 2 charstring bytes.
3. **Charset** — glyph name → GID map (uses post.names if available; else `gid{N}`).
4. **Private DICT** — default width, nominal width, hint-mask operators (no-op when source has no hints).
5. **Global / local subroutines** — empty INDEXs initially; TODO 06 wires hint subroutines.

The existing `Tables::Cff` BinData record already declares the on-disk structure; the builder produces the values to populate it.

## Out of scope

- CFF2 (variable fonts) — TODO 06.
- Subroutine packing / optimization — `Optimizers::SubroutineOptimizer` already exists for Type 1; CFF equivalent is a separate task.
- CID-keyed fonts with multi-FD — single FD only initially.

## Effort

~2-3 days.

## Dependencies

None (the placeholder CFF was the only thing blocking, and we're replacing it).

## Acceptance criteria

- New spec `spec/fontisan/ufo/compile/otf_compiler/cff_builder_spec.rb` covers:
  - Single-glyph font (`.notdef` + one outline) → valid CFF
  - Multi-glyph font with quadratic curves → charstrings use rcurveto correctly
  - Multi-glyph font with TrueType cubic curves → curve conversion to Type 2 cubic
  - Charset ordering matches maxp.numGlyphs
- Round-trip: UFO → OTF → re-read → contours match (within Type 2 quantization tolerance)
- `fontisan convert font.ufo --to otf` produces a font that loads in fontTools and Chrome.
