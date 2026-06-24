---
title: audit
---

# audit

Produce a complete per-face font audit report — identity, style, metrics,
coverage, licensing, hinting, color capabilities, variable-font detail,
OpenType layout features, and Unicode/CLDR aggregation.

`audit` is the successor to `otfinfo`: it covers everything `otfinfo`
reports plus a great deal more (coverage, hinting, color, variation,
layout, language coverage), and supports collections, compare mode, and
whole-library summaries.

## Quick Reference

```bash
# One face
fontisan audit FONT.ttf

# Collection (one report per face)
fontisan audit COLLECTION.ttc

# Whole library
fontisan audit DIR/ --recursive --summary

# Compare two fonts or saved reports
fontisan audit --compare A.ttf B.ttf
```

## Variants

| Variant | What it does | Output |
|---------|-------------|--------|
| `audit FONT.ttf` | One AuditReport for the single face | `AuditReport` |
| `audit COLLECTION.ttc` | One AuditReport per face (in source order) | `Array<AuditReport>` |
| `audit DIR/ --recursive --summary` | Walk the directory, summarize the library | `LibrarySummary` |
| `audit --compare A B` | Diff two faces or two saved reports | `AuditDiff` |

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format: `text` (default), `yaml`, `json` |
| `--output PATH`, `-o` | Write to a directory (collection/library), a file (single/compare), or stdout |
| `--font-index N` | Audit only face N of a collection (default: all) |
| `--brief` | Fast inventory — skip metrics/hinting/color/layout/UCD/CLDR |
| `--all-codepoints` | Include the full per-codepoint list (defaults to a compact range view) |
| `--ucd-version VER` | Aggregate against this UCD version (`latest` to probe) |
| `--with-language-coverage` | Compute CLDR language coverage % (auto-downloads CLDR on first use) |
| `--cldr-version VER` | CLDR version to use (`latest` to probe) |
| `--compare` | Diff two inputs (requires exactly two paths) |
| `--recursive` | Library mode: walk into subdirectories |
| `--summary` | Library mode: produce a `LibrarySummary` over a directory |

## Brief Mode

`--brief` runs only the cheap name-table extractors (provenance, identity,
style, licensing, coverage) and skips metrics, hinting, color,
variation, OpenType layout, UCD block/script aggregation, and CLDR
language coverage. Useful for taking a fast inventory of large libraries.

```bash
fontisan audit FONT.ttf --brief
fontisan audit DIR/ --recursive --summary --brief
```

Note: `audit --brief` is distinct from `info --brief`. `info --brief`
loads only 6 tables; `audit --brief` still loads the full font (Coverage
reads `cmap`) but selects a cheaper extractor subset.

## Single-Face Audit

```bash
# Text formatter (default)
fontisan audit FONT.ttf

# YAML (machine-readable)
fontisan audit FONT.ttf --format yaml

# JSON
fontisan audit FONT.ttf --format json | jq '.licensing'

# Write to disk
fontisan audit FONT.ttf -o report.yaml
```

Sample text output (truncated):

```
NotoSans-Regular
================================================================================
generated_at: 2026-06-24T18:11:39Z      fontisan: 0.2.20
source_sha256: f5f552c8c5edb61fe6efb824baf4d4de47b1a8689ab4925ff43f7bd6a4ebece5
source_file:   /path/to/NotoSans-Regular.ttf
source_format: ttf                      layout: single face (1/1)

IDENTITY
  Family:           Noto Sans
  Subfamily:        Regular
  Full name:        Noto Sans Regular
  PostScript:       NotoSans-Regular
  Version:          Version 2.015; ttfautohint (v1.8.4.7-5d5b)
  Revision:         2.0149993896484375

STYLE
  Weight class:     400 (Regular)
  Width class:      5 (Medium)
  Bold:             no
  Italic:           no
  PANOSE:           2 11 5 2 4 5 4 2 2 4

COVERAGE
  Codepoints:       3094
  Glyphs:           4515
  cmap subtables:   4, 12
  Ranges (top 10):  U+0000-U+0000, U+000D-U+000D, U+0020-U+007E, ...
  Unicode scripts:  Latin, ...

LICENSING
  License URL:      https://scripts.sil.org/OFL
  Embedding:        0x0000 (Editable embedding)

METRICS
  Units per em:     1000
  Ascender:         1160
  Descender:        -288
  ...

UNICODE BLOCKS
  Basic Latin                   95 / 128   74.2%
  Latin-1 Supplement            96 / 128   75.0%
  ...

VARIABLE FONT
  Axes:             wght (100–900, default 400)
  Named instances:  9

OPENTYPE LAYOUT
  Scripts:          latn, cyrl, grek, ...
  Features:         c2sc, calt, case, dlig, dnom, frac, kern, liga, ...

LANGUAGE COVERAGE
  en:  99.2%
  fr:  97.4%
  ...
```

## Collections

For TTC/OTC/dfont, one report is produced per face in source order.

```bash
# Audit every face
fontisan audit COLLECTION.ttc

# Audit only face 2
fontisan audit COLLECTION.ttc --font-index 2

# Write one file per face into a directory
fontisan audit COLLECTION.ttc -o reports/

# Resulting files use the postscript name with a 2-digit index prefix:
# 00-NotoSans-Regular.yaml
# 01-NotoSans-Bold.yaml
# 02-NotoSerif-Italic.yaml
```

## Compare Mode

`--compare` diffs two inputs. Each input is one of:

- A previously saved audit report (`.yaml` / `.yml` / `.json`)
- A font file (audited on-the-fly)

Mixed inputs are allowed — useful for tracking a font's evolution
against a checked-in baseline.

```bash
# Two live fonts
fontisan audit --compare a.ttf b.ttf

# Saved baseline vs. live
fontisan audit --compare baseline.yaml new.ttf

# Two saved reports
fontisan audit --compare v1.yaml v2.yaml -o diff.yaml
```

The output is an `AuditDiff` containing:

- `field_changes` — scalar field-level changes (e.g. weight_class 400 → 700)
- `codepoints` — added/removed/unchanged codepoint counts
- `added_features` / `removed_features`
- `added_scripts` / `removed_scripts`
- `added_blocks` / `removed_blocks`
- `added_languages` / `removed_languages`

## Library Mode

Point `audit` at a directory with `--recursive` and/or `--summary` to
scan a whole library of fonts.

```bash
# Flat directory
fontisan audit lib/ --summary

# Walk subdirectories
fontisan audit lib/ --recursive --summary

# YAML for downstream processing
fontisan audit lib/ --recursive --summary --format yaml -o library.yaml
```

The output is a `LibrarySummary` containing:

- `root_path`, `total_files`, `total_faces`, `scanned_extensions`
- `aggregate_metrics` — total codepoints/glyphs/bytes summed across faces
- `script_coverage` — per-script face counts and lists
- `duplicate_groups` — files grouped by `source_sha256` (size > 1)
- `license_distribution` — face counts per `license_url`
- `per_face_reports` — the full per-face reports used to aggregate

Files that fail to load (corrupt, unsupported) are listed on stderr as
`skipped <path>` and excluded from the summary.

## UCD Aggregation

By default, audit aggregates codepoints against the configured-default
UCD version, producing:

- `blocks` — per-Unicode-block coverage rows (name, range, total, covered, fill_ratio, complete)
- `unicode_scripts` — distinct scripts present in the font

Override with `--ucd-version`:

```bash
# Use a specific UCD version
fontisan audit FONT.ttf --ucd-version 16.0.0

# Probe and use the latest
fontisan audit FONT.ttf --ucd-version latest
```

Manage the local UCD cache with `fontisan ucd`:

```bash
fontisan ucd status
fontisan ucd list
fontisan ucd download 17.0.0
```

## CLDR Language Coverage

`--with-language-coverage` computes per-language coverage % using CLDR
exemplar sets. The first invocation downloads the CLDR data
(~MBs); subsequent invocations use the cache.

```bash
fontisan audit FONT.ttf --with-language-coverage

# Use a specific CLDR version
fontisan audit FONT.ttf --with-language-coverage --cldr-version 45
```

Manage the CLDR cache with `fontisan cldr`:

```bash
fontisan cldr status
fontisan cldr list
fontisan cldr download 45
```

## Ruby API

### Single face

```ruby
require "fontisan"

# Returns an AuditReport for a single font, or an Array<AuditReport>
# for a collection (one per face).
report = Fontisan::Commands::AuditCommand.new("font.ttf",
                                              ucd_version: "17.0.0").run

puts report.family_name
puts report.total_codepoints
puts report.licensing.license_url
puts report.blocks.first.fill_ratio
```

### Compare

```ruby
diff = Fontisan::Commands::AuditCompareCommand.new(
  "baseline.yaml", "new.ttf", ucd_version: "17.0.0"
).run

diff.field_changes.each { |c| puts "#{c.field}: #{c.left} → #{c.right}" }
puts "added codepoints: #{diff.codepoints.added_count}"
```

### Library summary

```ruby
cmd = Fontisan::Commands::AuditLibraryCommand.new(
  "lib/", recursive: true, options: { ucd_version: "17.0.0" }
)
summary = cmd.run
cmd.skipped.each { |path| warn "skipped #{path}" }

summary.script_coverage.each do |row|
  puts "#{row.script}: #{row.face_count} faces"
end
summary.duplicate_groups.each do |group|
  puts "duplicate #{group.source_sha256[0,8]}: #{group.files.join(', ')}"
end
```

### Brief mode

```ruby
# Use the audit_brief: key (NOT brief:, which would trigger metadata-only
# font loading via BaseCommand).
report = Fontisan::Commands::AuditCommand.new(
  "font.ttf", audit_brief: true, ucd_version: "17.0.0"
).run
```

## Related Commands

- [info](/cli/info) — Lighter-weight font metadata (replaces `otfinfo -i`)
- [tables](/cli/tables) — Raw OpenType table listing
- [features](/cli/features) — Just GSUB/GPOS features
- [scripts](/cli/scripts) — Just supported scripts
- [validate](/cli/validate) — Pass/fail quality checks (audit is descriptive; validate is prescriptive)
