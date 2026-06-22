---
title: Web Font Formats
---

# Web Font Formats

Fontisan supports conversion to web-optimized formats (WOFF and WOFF2) for optimal web delivery.

## Overview

| Format | Compression | Browser Support | Use Case |
|--------|-------------|-----------------|----------|
| WOFF | zlib | All modern browsers (IE 9+) | Wide compatibility |
| WOFF2 | Brotli | Modern browsers | Smallest size |

The format you pick **is** the algorithm choice — WOFF 1.0 mandates zlib,
WOFF2 mandates Brotli. There is no separate `--compression` flag. Each
format exposes its algorithm's tunable parameters instead (level, quality,
threshold, transform).

## WOFF2

WOFF2 provides 30-50% smaller files than TTF/OTF.

### Conversion

```bash
# Basic WOFF2 conversion
fontisan convert font.ttf --to woff2 --output font.woff2

# From any format
fontisan convert font.otf --to woff2 --output font.woff2
fontisan convert font.pfb --to woff2 --output font.woff2
```

### Recommended Options

```ruby
Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# opening: {}
# generating: { brotli_quality: 11, transform_tables: true,
#              optimize_tables: true, preserve_metadata: true }
```

### WOFF2 Benefits

- 30-50% smaller than TTF/OTF
- Broader browser support
- Preprocessing transforms for better compression

## WOFF

WOFF provides wider compatibility with older browsers.

### Conversion

```bash
# Basic WOFF conversion
fontisan convert font.ttf --to woff --output font.woff
```

### Options

```ruby
options = Fontisan::ConversionOptions.new(
  to: :woff,
  generating: {
    zlib_level: 9,           # max zlib compression
    preserve_metadata: true
  }
)
```

For maximum legacy reach use the `:legacy_web` preset:

```ruby
Fontisan::ConversionOptions.from_preset(:legacy_web)
# From: :otf, To: :woff
# generating: { zlib_level: 9, optimize_tables: true, preserve_metadata: true }
```

## web_optimized Preset

Optimize fonts for web delivery:

```ruby
Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# opening: {}
# generating: { brotli_quality: 11, transform_tables: true,
#              optimize_tables: true, preserve_metadata: true }
```

### Use Cases

- Web font delivery
- Reducing page load time
- Bandwidth optimization

## Type 1 → Web Fonts

Convert legacy Type 1 fonts to web formats.

### Workflow

```
Type 1 → OTF → WOFF2
```

### CLI

```bash
# Direct conversion
fontisan convert font.pfb --to woff2 --output font.woff2 --preset type1_to_modern

# Step by step
fontisan convert font.pfb --to otf --output font.otf --generate-unicode
fontisan convert font.otf --to woff2 --output font.woff2
```

### Options

```ruby
# Via OTF intermediate
options = Fontisan::ConversionOptions.new(
  opening: { decompose_composites: false, generate_unicode: true },
  generating: {
    brotli_quality: 11     # WOFF2
    # For WOFF instead, use: zlib_level: 9
  }
)
```

## Compression Knobs

Each web format exposes its algorithm's parameters. Knobs that don't apply
to the requested target are rejected up-front with a clear error.

### WOFF (zlib)

| Option | CLI | Range | Default | Notes |
|--------|-----|-------|---------|-------|
| `zlib_level` | `--zlib-level=N` | 0–9 | 6 | 0 = no compression, 9 = smallest |
| `uncompressed` | `--uncompressed` | bool | false | Store tables uncompressed (legal per WOFF 1.0 §5.1; `compLength == origLength`) |
| `compression_threshold` | `--compression-threshold=N` | bytes | 100 | Skip compression for tables smaller than N |

```ruby
# Max zlib compression
options = Fontisan::ConversionOptions.new(
  to: :woff,
  generating: { zlib_level: 9 }
)

# No compression (legal per spec; useful for tooling pipelines)
options = Fontisan::ConversionOptions.new(
  to: :woff,
  generating: { uncompressed: true }
)
```

### WOFF2 (Brotli)

| Option | CLI | Range | Default | Notes |
|--------|-----|-------|---------|-------|
| `brotli_quality` | `--brotli-quality=N` | 0–11 | 11 | 0 = fastest, 11 = smallest |
| `transform_tables` | `--[no-]transform-tables` | bool | false | Apply glyf/loca and hmtx transformations |

```ruby
# Smallest possible WOFF2
options = Fontisan::ConversionOptions.new(
  to: :woff2,
  generating: { brotli_quality: 11, transform_tables: true }
)
```

### Cross-format validation

Passing a WOFF knob to a WOFF2 target (or vice versa) is rejected at
conversion time by `FormatConverter.validate_options_for_target!`:

```ruby
# Rejected at convert time: brotli_quality does not apply to woff
Fontisan.convert('font.ttf', to: :woff, output: 'font.woff',
                 brotli_quality: 11)
# => Fontisan::Error: ... Option(s) :brotli_quality do not apply to --to woff.
#    Accepted for woff: zlib_level, uncompressed, compression_threshold,
#                       metadata_xml, private_data
```

The CLI equivalent exits 1 with the same message.

## Table Transforms (WOFF2)

WOFF2 supports table transformations for better compression:

| Table | Transform |
|-------|-----------|
| glyf | Combined with loca, bbox deltas |
| hmtx | Combined with hhea |
| CFF | De-subroutinization |

```ruby
options = Fontisan::ConversionOptions.new(
  to: :woff2,
  generating: { transform_tables: true }
)
```

CLI equivalent:

```bash
fontisan convert font.ttf --to woff2 --output font.woff2 --transform-tables
```

## Metadata Handling

### Preserve Metadata

```bash
fontisan convert font.ttf --to woff2 --preserve-metadata
```

Keeps copyright, license, and other metadata intact.

### Strip Metadata

```bash
fontisan convert font.ttf --to woff2 --strip-metadata
```

Removes metadata for smaller file size (check license first).

## Examples

### Complete Web Font Workflow

```ruby
require 'fontisan'

# Load source
font = Fontisan::FontLoader.load('source.ttf')

# Create WOFF2
woff2_options = Fontisan::ConversionOptions.from_preset(:web_optimized)
Fontisan::FontWriter.write(font, 'font.woff2', options: woff2_options)

# Create WOFF for older browsers (max zlib)
woff_options = Fontisan::ConversionOptions.from_preset(:legacy_web)
Fontisan::FontWriter.write(font, 'font.woff', options: woff_options)
```

### Top-level Fontisan.convert

```ruby
# WOFF2 with max Brotli
Fontisan.convert('font.ttf', to: :woff2, output: 'font.woff2',
                 brotli_quality: 11, transform_tables: true)

# WOFF with max zlib (for IE / older browsers)
Fontisan.convert('font.ttf', to: :woff, output: 'font.woff', zlib_level: 9)

# WOFF stored uncompressed (legal per WOFF 1.0 §5.1)
Fontisan.convert('font.ttf', to: :woff, output: 'font.woff', uncompressed: true)
```

### Batch Web Conversion

```bash
# Convert all TTF files to WOFF2 with max Brotli
for f in fonts/*.ttf; do
  fontisan convert "$f" --to woff2 --output "web/$(basename "${f%.ttf}.woff2")" \
    --brotli-quality 11 --transform-tables
done
```

### Compare File Sizes

```bash
# Check file sizes
ls -la font.ttf font.woff font.woff2

# Example output:
# -rw-r--r--  font.ttf    124,500 bytes
# -rw-r--r--  font.woff    98,200 bytes   (21% smaller)
# -rw-r--r--  font.woff2   62,300 bytes   (50% smaller)
```

## Browser Support

| Browser | WOFF | WOFF2 |
|---------|------|-------|
| Chrome | 5+ | 36+ |
| Firefox | 3.6+ | 35+ |
| Safari | 5.1+ | 12+ |
| Edge | All | 14+ |
| IE | 9+ | — |

For maximum compatibility, provide both WOFF and WOFF2.
