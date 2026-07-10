# Fontisan Improvements Backlog

This directory tracks all known improvement work, ordered by priority.
Each file is `NN-short-name.md` where `NN` is the priority order.

## Priorities

### P0 — Correctness gaps (open bugs / silent failures)
- [01 — CBDT/CBLC GID-stable propagation](01-cbdt-cblc-gid-stable-propagation.md)
- [02 — Collection-mode outline-priority regression](02-collection-outline-priority.md)

### P1 — High-value features
- [03 — `fontisan audit` command (identity+style+features lens)](03-fontisan-audit-command.md)
- [04 — UFO composite glyph encoding](04-ufo-composite-glyph-encoding.md)
- [05 — OTF compiler real CFF charstrings](05-otf-compiler-real-cff.md)

### P2 — Specialist feature parity
- [x] ~~[07 — CPAL v1 header fields](07-cpal-v1-header-fields.md)~~ ✓ Done (v0.4.25)
- [x] ~~[08 — CFF standard string table](08-cff-standard-string-table.md)~~ ✓ Partial (SID 0-95, ASCII subset)
- [06 — CFF2 blend/vsindex operators](06-cff2-blend-vsindex-operators.md)
- [09 — Type 1 seac expansion](09-type1-seac-expansion.md)
- [10 — UFO image set + feature writers](10-ufo-image-set-feature-writers.md)
- [11 — kern groups.plist support](11-kern-groups-plist.md)

### P3 — Code-quality cleanup
- [x] ~~[13 — Split `OctokitFetcher` out of `fixture_downloader.rb`](13-split-octokit-fetcher.md)~~ ✓ Done (v0.4.24)
- [x] ~~[12 — `cbdt_fixture.rb` full BinData conversion](12-cbdt-fixture-bindata-conversion.md)~~ ✓ Partial (head/hhea/post converted; os2/name/hmtx/cmap remain)
- [14 — Rubocop baseline chip (per-namespace)](14-rubocop-baseline-chip.md)

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
