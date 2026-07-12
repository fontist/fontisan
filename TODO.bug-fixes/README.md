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
