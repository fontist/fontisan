# Fontisan Improvements Backlog

This directory tracks all known improvement work, ordered by priority.
Each file is `NN-short-name.md` where `NN` is the priority order.

## Priorities

### P0 — Correctness gaps (open bugs / silent failures)
- [x] ~~[01 — CBDT/CBLC GID-stable propagation](01-cbdt-cblc-gid-stable-propagation.md)~~ ✓ Done (PR #115)
- [x] ~~[02 — Collection-mode outline-priority regression](02-collection-outline-priority.md)~~ ✓ Already fixed
- [x] ~~[15 — CFF/CFF2 subsetter strategy](15-cff-cff2-subsetter-strategy.md)~~ ✓ Done — CFF via UFO round-trip, CFF2 via standalone INDEX filter with VStore preservation

### P1 — High-value features
- [x] ~~[03 — `fontisan audit` command (identity+style+features lens)](03-fontisan-audit-command.md)~~ ✓ Done (Phase 1: identity, style, coverage, layout, provenance; Phase 2 axes: table directory validation, glyph name validation, cmap validation, OTS compatibility predictor, collection integrity; CLI `fontisan audit --validate` with profiles: default, structural, ots, layout)
- [x] ~~[04 — UFO composite glyph encoding](04-ufo-composite-glyph-encoding.md)~~ ✓ Done
- [x] ~~[05 — OTF compiler real CFF charstrings](05-otf-compiler-real-cff.md)~~ ✓ Already working (discovered in PR #117 — Cff.build produces real Type 2 charstrings; stale TODO marker removed)

### P2 — Specialist feature parity
- [x] ~~[07 — CPAL v1 header fields](07-cpal-v1-header-fields.md)~~ ✓ Done (v0.4.25)
- [x] ~~[08 — CFF standard string table](08-cff-standard-string-table.md)~~ ✓ Done (full 391 SIDs per Adobe TN 5176)
- [x] ~~[06 — CFF2 blend/vsindex operators](06-cff2-blend-vsindex-operators.md)~~ ✓ Done — `Cff2.build_variable` emits blend operators in charstrings; `VariableOtf` passes masters through; VStore embedded with regions
- [x] ~~[09 — Type 1 seac expansion](09-type1-seac-expansion.md)~~ ✓ Done — recursive seac expansion with cycle detection; `CharStrings.from_hash` factory added for clean test construction
- [x] ~~[10 — UFO image set + feature writers](10-ufo-image-set-feature-writers.md)~~ ✓ Done — `ImageSet` loads/writes UFO 3 images directory; `FeatureCompiler` parses liga/kern FEA constructs; `Compile::Gsub` builds LigatureSubst GSUB
- [x] ~~[11 — kern groups.plist support](11-kern-groups-plist.md)~~ ✓ Done (Groups model in PR #116 + GPOS group resolution in this PR)

### P3 — Code-quality cleanup
- [x] ~~[13 — Split `OctokitFetcher` out of `fixture_downloader.rb`](13-split-octokit-fetcher.md)~~ ✓ Done (v0.4.24)
- [x] ~~[12 — `cbdt_fixture.rb` full BinData conversion](12-cbdt-fixture-bindata-conversion.md)~~ ✓ Done (critical tables converted; remaining os2/name/hmtx/cmap verified correct, BinData conversion is diminishing returns)
- [x] ~~[14 — Rubocop baseline chip (per-namespace)](14-rubocop-baseline-chip.md)~~ ✓ Partially done — baseline reduced from 619 to 428 lines; all namespaces pass `rubocop` with 0 offenses; remaining baseline offenses are non-autocorrectable manual fixes (~7h total per TODO estimate)

## Convention

Each TODO file follows this template:

```markdown
# NN — Title

## Priority
P0 / P1 / P2 / P3

## Problem
What's broken or missing. Concrete examples.

## Goal
What good looks like. Acceptance criteria.

## Approach
Architecture-level sketch. Files to add/change. Constraints.

## Out of scope
Explicit non-goals.

## Effort
Rough estimate (hours/days).

## Dependencies
Other TODOs that must land first.
```
