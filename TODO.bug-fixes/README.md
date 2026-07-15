# Fontisan Bug Fix Backlog

Tracks correctness gaps discovered during codebase investigation.
Each file is `NN-short-name.md` where `NN` is the priority order.

## Priorities

### P0 — Correctness bugs (wrong data for specific font types)
- [x] ~~[01 — CFF Expert charset placeholder](01-cff-expert-charsets.md)~~ ✓ Done (v0.4.40)
- [x] ~~[02 — CFF2 subroutine call stubs](02-cff2-subroutine-stubs.md)~~ ✓ Done (v0.4.40)
- [x] ~~[09 — Type 1 → CFF seac expansion](09-type1-cff-seac-expansion.md)~~ ✓ Done

### P1 — Feature gaps (non-functional code paths)
- [x] ~~[03 — Variation subsetter placeholders](03-variation-subsetter-placeholders.md)~~ ✓ Done (v0.4.40)
- [x] ~~[04 — UFO image compile round-trip](04-ufo-image-compile-roundtrip.md)~~ ✓ Done (v0.4.40)
- [x] ~~[06 — Variable font instance WOFF2 output](06-instance-woff2-output.md)~~ ✓ Done (v0.4.41)
- [x] ~~[10 — TTF → Type 1 composite glyph handling](10-ttf-type1-composite-glyphs.md)~~ ✓ Done

### P2 — Documentation cleanup
- [x] ~~[05 — Stale CFF comment](05-stale-cff-comment.md)~~ ✓ Done (v0.4.40)

### P3 — Code quality violations
- [x] ~~[07 — Encapsulation violations (instance_variable_get/set, send to private)](07-encapsulation-violations.md)~~ ✓ Done (v0.4.42)
- [x] ~~[08 — respond_to? duck typing violations](08-respond-to-violations.md)~~ ✓ Done (v0.4.42)
- [x] ~~[11 — Remaining respond_to? violations](11-remaining-respond-to.md)~~ ✓ Done

### P3 — Encapsulation and architecture cleanup (post-#135 audit)
- [x] ~~[12 — Type 1 generators duck-typing](12-type1-generators-duck-typing.md)~~ ✓ Done (#136)
- [x] ~~[13 — Hint extractor duck-typing](13-hint-extractor-duck-typing.md)~~ ✓ Done (#136)
- [x] ~~[14 — Font interface type checks](14-font-interface-type-checks.md)~~ ✓ Done (#136)
- [x] ~~[15 — Glyph type checks + SimpleGlyph#points bug](15-glyph-type-checks-and-simple-glyph-points-bug.md)~~ ✓ Done (#136)
- [x] ~~[16 — Variation table checks](16-variation-table-checks.md)~~ ✓ Done (#137)
- [x] ~~[17 — UFO and Stitcher cleanup](17-ufo-and-stitcher-cleanup.md)~~ ✓ Done (#136)
- [x] ~~[18 — Generic value and IO checks](18-generic-value-and-io-checks.md)~~ ✓ Done (#137)
- [x] ~~[19 — Hand-rolled serialization migration to lutaml-model](19-serialization-migration.md)~~ ✓ Done (#137)

### P3 — Final encapsulation cleanup (post-#136 audit)
- [x] ~~[20 — Variation validator type checks](20-variation-validator-type-checks.md)~~ ✓ Done (#137)
- [x] ~~[21 — XML builder send() → tag!](21-xml-builder-send.md)~~ ✓ Done (#137)
- [x] ~~[22 — Type1Converter font_info fields](22-type1-converter-font-info.md)~~ ✓ Done (#137)
- [x] ~~[23 — Boundary type checks (padding, base_record)](23-boundary-type-checks.md)~~ ✓ Done (#137)
- [x] ~~[24 — Validator dynamic field_key](24-validator-dynamic-field-key.md)~~ ✓ Done (#137)
- [x] ~~[25 — Serialization migration to lutaml-model](25-serialization-migration.md)~~ ✓ Done (#137)
- [x] ~~[26 — Variation preserver spec migration](26-variation-preserver-spec-migration.md)~~ ✓ Done (#137)

### P3 — Architecture polish (post-#137 audit)
- [ ] [27 — Table class registry (OCP: eliminate case/when tag dispatch)](27-table-class-registry.md)
- [ ] [28 — Spec doubles cleanup](28-spec-doubles-cleanup.md)
