---
title: WOFF & WOFF2
---

# WOFF & WOFF2

Web Open Font Format (WOFF and WOFF2) are optimized for web delivery.

## Overview

| Format | Compression | Browser Support |
|--------|-------------|-----------------|
| WOFF | zlib | All modern browsers (IE 9+) |
| WOFF2 | Brotli | Modern browsers |

The format you pick **is** the algorithm choice — WOFF 1.0 mandates zlib,
WOFF2 mandates Brotli. Each format exposes its algorithm's parameters
(level, quality, transform) rather than offering a separate algorithm
selector.

## WOFF2 Benefits

- 30-50% smaller than TTF/OTF
- Preprocessing transforms for better compression
- Modern browser support

## Converting to WOFF

```bash
# From TTF
fontisan convert font.ttf --to woff --output font.woff

# From OTF
fontisan convert font.otf --to woff --output font.woff

# Max zlib compression
fontisan convert font.ttf --to woff --output font.woff --zlib-level 9
```

## Converting to WOFF2

```bash
# From TTF
fontisan convert font.ttf --to woff2 --output font.woff2

# From OTF
fontisan convert font.otf --to woff2 --output font.woff2

# From Type 1
fontisan convert font.pfb --to woff2 --output font.woff2

# Smallest possible output (max Brotli + table transforms)
fontisan convert font.ttf --to woff2 --output font.woff2 \
  --brotli-quality 11 --transform-tables
```

## API Usage

```ruby
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# generating: { brotli_quality: 11, transform_tables: true,
#              optimize_tables: true, preserve_metadata: true }

Fontisan::FontWriter.write(font, 'font.woff2', options: options)
```

## Compression Knobs

### WOFF (zlib)

| Option | CLI | Range | Default |
|--------|-----|-------|---------|
| `zlib_level` | `--zlib-level=N` | 0–9 | 6 |
| `uncompressed` | `--uncompressed` | bool | false |
| `compression_threshold` | `--compression-threshold=N` | bytes | 100 |

```ruby
generating: { zlib_level: 9 }           # max zlib
generating: { uncompressed: true }      # legal per WOFF 1.0 §5.1
```

### WOFF2 (Brotli)

| Option | CLI | Range | Default |
|--------|-----|-------|---------|
| `brotli_quality` | `--brotli-quality=N` | 0–11 | 11 |
| `transform_tables` | `--[no-]transform-tables` | bool | false |

```ruby
generating: { brotli_quality: 11, transform_tables: true }
```

Cross-format misuse (e.g. `brotli_quality` on `:woff`) raises
`ArgumentError` from `FormatConverter.validate_options_for_target!`.

## Table Transforms

WOFF2 supports table transformations:

| Table | Transform |
|-------|-----------|
| glyf | Combined with loca |
| hmtx | Combined with hhea |
| CFF | De-subroutinization |

```ruby
options = Fontisan::ConversionOptions.new(
  to: :woff2,
  generating: { transform_tables: true }
)
```

## Converting from WOFF

```bash
# WOFF to TTF
fontisan convert font.woff --to ttf --output font.ttf

# WOFF2 to OTF
fontisan convert font.woff2 --to otf --output font.otf
```

## Browser Support

| Browser | WOFF | WOFF2 |
|---------|------|-------|
| Chrome | 5+ | 36+ |
| Firefox | 3.6+ | 35+ |
| Safari | 5.1+ | 12+ |
| Edge | All | 14+ |
| IE | 9+ | — |

## Best Practices

1. **Use WOFF2 primarily** — Best compression
2. **Provide WOFF fallback** — For older browsers (IE 9+)
3. **Keep original** — For editing
4. **Preserve metadata** — Unless stripping for size
