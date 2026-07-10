# 14 — Rubocop baseline chip (per-namespace)

## Priority
P3

## Problem

PR #111's `rubocop -A --auto-gen-config` baseline refresh tracked ~9600 remaining offenses. The `.rubocop_todo.yml` file is now ~800 lines of `Exclude:` lists. Layout/Style cops dominate (most are auto-correctable; the rest need manual fixes).

Leaving the baseline in this state makes future rubocop improvements invisible — new offenses are buried in baseline noise, and contributors can't see whether their PR is clean vs. baseline-burdened.

## Goal

Reduce baseline count to < 1000 offenses via per-namespace PRs:

| Namespace | Approximate count | Priority |
|-----------|-------------------|----------|
| `lib/fontisan/tables/` | ~3000 | High (well-understood) |
| `lib/fontisan/ufo/compile/` | ~2500 | High |
| `lib/fontisan/stitcher/` | ~800 | Medium |
| `lib/fontisan/converters/` | ~500 | Medium |
| `lib/fontisan/type1/` | ~400 | Medium |
| `lib/fontisan/collection/` | ~300 | Medium |
| `lib/fontisan/subset/` | ~300 | Medium (recent PR #106 work) |
| `lib/fontisan/woff2/` | ~250 | Medium |
| `lib/fontisan/optimizers/` | ~200 | Low |
| `lib/fontisan/pipeline/` | ~200 | Low |
| `lib/fontisan/commands/` | ~150 | Low |
| `lib/fontisan/validators/` | ~100 | Low |
| `lib/fontisan/binary/` | ~100 | Low |
| `spec/` | ~1500 | Low |

## Approach

One PR per namespace. Each PR:

1. Runs `rubocop -A lib/fontisan/<namespace>/` to auto-correct everything possible.
2. Manually fixes what auto-correct couldn't (typically: complex Layout cops, naming).
3. Updates `.rubocop_todo.yml` to drop the now-cleaned `Exclude:` entries.
4. Verifies the full test suite still passes.

Order: tables first (highest count, lowest risk — table parsing is purely structural).

## Out of scope

- Disabling cops project-wide — these are real issues, not noise.
- Refactoring architectural patterns rubocop flags (e.g., long methods) — separate refactors.

## Effort

~30 minutes per namespace on average. ~7 hours total.

## Dependencies

None.

## Acceptance criteria

- `.rubocop_todo.yml` < 100 lines (from ~800).
- `bundle exec rubocop` reports 0 offenses.
- All existing specs pass after each namespace PR.
- No behavior change (pure style/layout).
