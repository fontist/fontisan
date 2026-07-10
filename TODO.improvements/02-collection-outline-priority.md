# 02 — Collection-mode outline-priority regression

## Priority
P0

## Problem

`spec/fontisan/stitcher/outline_priority_spec.rb:160` ("write_collection preserves outline-first cmap priority across faces") was unblocked for single-face mode in PR #108 but the **collection variant** is still skipped:

```ruby
skip "Stitcher currently raises on a CBDT source without at least one outline codepoint in each face — " \
     "collection-mode coverage needs CbdtPropagator hardening tracked separately."
```

When the Stitcher builds a TTC/OTC, each face compiles independently. The CBDT source is global — its placeholders need to land in EVERY face that covers any of its codepoints. The current `CbdtPropagator#add_placeholder_glyphs` raises if a face has no outline glyph from any other donor (the CBDT source alone can't seed a face).

## Goal

The skipped test passes. A CBDT source can be stitched into a collection where some faces cover only CBDT codepoints (no outline donor coverage). Each face gets the CBDT/CBLC tables propagated.

## Approach

Two pieces:

1. **`CbdtPropagator#add_placeholder_glyphs`** — relax the "must have an outline codepoint" precondition. Allow a face to be seeded with just CBDT placeholders (plus the `.notdef` that's always required).

2. **`CbdtPropagator#propagate_tables_into`** — for collections, run per-face rather than once. The collection writer already iterates faces; this is a matter of plumbing.

This depends on TODO 01 (GID-stable propagation) because the collection case multiplies the GID-mapping complexity — each face has its own compiled GID space.

## Out of scope

- Multi-CBDT-source support (the `MultipleCbdtSourcesError` guard remains).
- Cross-face glyph deduplication (already handled by the existing dedup pass).

## Effort

~2 hours once TODO 01 lands.

## Dependencies

- TODO 01 (CBDT/CBLC GID-stable propagation).

## Acceptance criteria

- The skipped test at `outline_priority_spec.rb:160` is unskipped and passes.
- A new test covers the "CBDT-only face" case (a face with no outline donor coverage, only CBDT placeholders).
- `MultipleCbdtSourcesError` is still raised when two CBDT sources are declared.
