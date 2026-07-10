# 03 — `fontisan audit` command (identity+style+features lens)

## Priority
P1

## Problem

The `fontist-archive-private` pipeline currently reaches into Fontisan internals to extract font identity + metadata:

```ruby
# Current (wrong) approach — manual cmap + table poking
font = Fontisan::FontLoader.load(font_path)
cmap = font.table("cmap")
codepoints = cmap ? cmap.unicode_mappings.keys : []
# ...plus ad-hoc reads of name, OS/2, head, fvar, GSUB, GPOS
```

Fragile and bypasses Fontisan's API. Fontisan has `InfoCommand` (font metadata) and `UnicodeCommand` (codepoint/glyph mappings), but neither produces a complete, self-describing audit record suitable for archival use.

## Goal

A `fontisan audit` command that produces a structured **font audit report** (YAML or JSON) covering what ucode's audit does NOT:

- **Identity** — name-table strings (family, full, PostScript, version)
- **Style** — OS/2 weight/width classes, head macStyle, fsSelection italic/bold, panose, fvar axes
- **Coverage facts** — total codepoints, total glyphs, cmap subtable provenance, optional codepoint list
- **OpenType layout** — GSUB/GPOS scripts (distinct from Unicode scripts), features list
- **Provenance** — `generated_at`, `fontisan_version`, `source_sha256`

## MECE split with ucode

ucode owns the Unicode-coverage axis (UCD parsing, block/script aggregation, per-codepoint glyph extraction). fontisan owns the font-identity axis.

| Concern | Owner |
|---------|-------|
| UCD fetching + parsing | ucode |
| Block/script aggregation from codepoints | ucode |
| Per-codepoint SVG extraction | ucode |
| HTML browsers | ucode |
| Font identity (name table) | **fontisan audit** |
| Style metadata (OS/2, head, fvar) | **fontisan audit** |
| OpenType scripts + features | **fontisan audit** |
| Source provenance (sha256, fontisan_version) | **fontisan audit** |
| cmap subtable provenance | **fontisan audit** |

**The fontisan audit does NOT bundle UCDXML parsing.** Block aggregation is delegated: fontisan audit accepts an optional pre-built ucode index path, OR emits the codepoint list and lets the consumer (fontist-archive) run ucode separately.

## Beyond ucode: font-health diagnostics

Beyond identity + style + features, fontisan's domain expertise enables audit axes ucode cannot provide:

1. **OTS-rejection predictor** — walk the compiled font's tables and flag patterns known to trip Chrome's OpenType Sanitizer (e.g., `loca.origLength` mismatches, glyf without 4-byte alignment, missing magic number). Reuses the rule set already encoded in `spec/fontisan/converters/woff2_ots_rejection_spec.rb`.

2. **Format-round-trip report** — when converting TTF → WOFF2 → TTF, report what changed: tables dropped, glyph count, total bytes. Identifies which conversions are lossless vs lossy. Reuses `Converters::FormatConverter` instrumentation.

3. **Variable-font readiness** — for fonts with `fvar`, check: axes within recommended ranges, named instances present, variation tables (`gvar`, `HVAR`, `MVAR`, `VVAR`) all present, no orphan deltas. Reuses `Variation::VariableFontProfile`.

4. **Hinting audit** — TrueType: are `cvt`, `fpgm`, `prep` present and syntactically valid? CFF: are subroutines present and properly referenced? Reuses `Hinting` namespace.

5. **Collection integrity** — for TTC/OTC: per-face identity, table deduplication stats (shared vs unique), cross-face PostScript name conflicts (which break font pickers).

These are all font-structure concerns ucode has no visibility into. The audit command can grow into these incrementally — start with identity+style+features, layer on diagnostics over time.

## Approach

### Models (`lib/fontisan/models/audit/`)

Use `lutaml-model` like all other fontisan models:

- `AuditReport` — top-level report, attributes per the schema below
- `AuditAxis` — variable-font axis descriptor
- `AuditFeature` — feature tag + scripts list

### Command (`lib/fontisan/commands/audit_command.rb`)

`Commands::AuditCommand` orchestrates — does NOT re-parse tables. Delegates to existing commands:

- `InfoCommand` — identity + name-table strings
- `UnicodeCommand` — codepoint list + cmap subtable provenance
- `ScriptsCommand` — `opentype_scripts`
- `FeaturesCommand` — `features`
- `FormatDetector` — `source_format`

This makes `AuditCommand` a thin orchestration layer.

### CLI (`lib/fontisan/cli.rb`)

```bash
# Standalone
fontisan audit Inter-Regular.ttf                    # → stdout (YAML)
fontisan audit Inter-Regular.ttf -o report.yaml     # → file
fontisan audit Inter-Regular.ttf --format json      # → stdout (JSON)

# Collection
fontisan audit Inter.ttc -o reports/                # → reports/Inter.ttc/{00..08}-*.yaml

# Single face from collection
fontisan audit Inter.ttc --font-index 6 -o Inter-Bold.yaml
```

### Output schema (one face per file)

```yaml
generated_at: 2026-07-10T12:30:00Z
fontisan_version: 0.4.24
source_file: Inter-Regular.ttf
source_sha256: 3b1a...
source_format: ttf

font_index: null
num_fonts_in_source: 1

# Identity
family_name: Inter
subfamily_name: Regular
full_name: Inter Regular
postscript_name: Inter-Regular
version: Version 4.000;git-a52131595
font_revision: 4.0

# Style
weight_class: 400
width_class: 5
italic: false
bold: false
panose: "2 0 5 3 0 0 0 0 0 0"
is_variable: false
axes: []

# Coverage
total_codepoints: 2857
total_glyphs: 1486
cmap_subtables: [4, 12, 14]
codepoints: [U+0000, U+0020, ...]   # omitted with --no-codepoints

# OpenType layout
opentype_scripts: [latn, cyrl]
features: [kern, liga, calt]
```

### Collection layout

```
reports/
  Inter.ttc/
    00-Inter-Regular.yaml
    01-Inter-Italic.yaml
    ...
    08-Inter-Black.yaml
```

Filename pattern: `{font_index:02d}-{postscript_name}.yaml`. Index prefix guarantees face-order sort and disambiguates broken fonts where two faces share a PostScript name.

## Out of scope

- UCDXML parsing (ucode's domain)
- Block/script aggregation (consumer runs ucode separately, OR a future `--with-ucode` flag calls ucode as a subprocess)
- HTML browsers (ucode's domain)
- Per-codepoint glyph extraction (ucode's 4-tier resolver)
- Reading formula YAML — this command reports what the FONT FILE declares
- Generating WOFF specimens (ConvertCommand's domain)

## Effort

~1-2 days.

## Dependencies

None directly. Existing commands (`InfoCommand`, `UnicodeCommand`, `ScriptsCommand`, `FeaturesCommand`) provide the data; `AuditCommand` just orchestrates.

## Acceptance criteria

- New spec `spec/fontisan/commands/audit_command_spec.rb` covers:
  - Standalone TTF → YAML + JSON output
  - Collection TTC → directory of N face reports
  - `--font-index N` → single-face report
  - `--no-codepoints` omits the codepoint list
  - Source sha256 matches `Digest::SHA256.file(path)`
  - Variable font with fvar → axes array populated
- New spec `spec/fontisan/models/audit_report_spec.rb` covers the model's serialization.
- CLI smoke test verifies `fontisan audit path/to/font.ttf` produces valid YAML on stdout.
- README/docs updated.
