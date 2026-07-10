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

## Beyond ucode: revised priority after self-debate

A critical self-debate (see commit history) culled several "diagnostic" features that overlap with existing tools. The surviving axes:

### Keep — high value, fontisan-unique
- **Identity + Style + Features** — justified for archival format (one YAML per face, with provenance). NOT a general font inspector.
- **Subset report** — when fontisan subsets, emit a structured report (glyph/codepoint/table breakdown). Web font engineers hit this daily; pyftsubset emits minimal output. fontisan has the subset infrastructure.
- **Cross-format equivalence** — `fontisan equivalent font.ttf font.woff2` → true/false + diff. Catches CDN regeneration bugs from stale masters. fontTools diffs are too noisy.
- **License/rights extraction** — OS/2 fsType embedding bits, name ID 13 license, head macStyle commercial-use hints. Compliance teams need this before redistribution. Currently buried.
- **Collection integrity** — narrow (CJK foundries, Apple system fonts) but real for that audience. Cheap to add once identity extraction exists.

### Drop — overlap with established tools
- ~~**OTS-rejection predictor**~~ — Chromium ships `ots-sanitize`, the actual tool Chrome uses. Reimplementing in Ruby means we're always behind Chrome's evolving rule set. Better: wrap ots-sanitize as subprocess.
- ~~**Format-round-trip report**~~ — WOFF2 is lossless by design; report would say "nothing changed" 99% of the time. TTF↔OTF outline-fidelity is a real check but it's one function, not an audit axis.
- ~~**Variable-font readiness**~~ — **fontbakery** owns this space. Hundreds of mature checks, Google Fonts uses it for every submission. Don't compete; wrap if needed.
- ~~**Hinting audit**~~ — audience is ~50 people worldwide. Modern web fonts ship largely unhinted. VF fonts don't use TT hints. Specialized tools (FontLab, ttfautohint) serve this niche better.

### Maybe later — niche but real
- **Performance profile** — glyph count, table-level bytes, predicted parse time. Mobile/embedded niche. Apple has internal tools; nothing public.
- **Identity hash** — canonical hash of (name + post + head + OS/2 identity) surviving lossless conversion. CDN/asset-pipeline use case.

The headline correction: the original proposal positioned fontisan audit as a "font inspector" competing with commodity tools. The actually-valuable features are **workflow-specific reports** (subset, conversion equivalence, license) that leverage fontisan's unique subsetting + conversion infrastructure. ucode can't do any of these.

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
