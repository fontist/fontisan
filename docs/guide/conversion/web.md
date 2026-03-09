---
title: Web Font Formats
---

# Web Font Formats

Fontisan supports conversion to web-optimized formats (WOFF and WOFF2) for optimal web delivery.

## Overview

| Format | Compression | Browser Support | Use Case |
|--------|-------------|-----------------|----------|
| WOFF | zlib | All modern browsers | Wide compatibility |
| WOFF2 | brotli | Modern browsers | Smallest size |

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
# generating: { compression: "brotli", transform_tables: true,
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
    compression: "zlib",
    preserve_metadata: true,
    add_private_data: false
  }
)
```

## web_optimized Preset

Optimize fonts for web delivery:

```ruby
Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# opening: {}
# generating: { compression: "brotli", transform_tables: true,
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
  generating: { compression: "brotli" }  # WOFF2
  # OR: generating: { compression: "zlib" }    # WOFF
)
```

## Compression Options

### brotli (WOFF2)

```ruby
generating: { compression: "brotli" }
```

- Best compression ratio
- Requires modern browsers
- Transforms tables for better compression

### zlib (WOFF)

```ruby
generating: { compression: "zlib" }
```

- Good compression
- Wide browser support
- No table transforms

### none

```ruby
generating: { compression: "none" }
```

- No compression
- For debugging

## Table Transforms

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

# Create WOFF for older browsers
woff_options = Fontisan::ConversionOptions.new(
  to: :woff,
  generating: { compression: "zlib", preserve_metadata: true }
)
Fontisan::FontWriter.write(font, 'font.woff', options: woff_options)
```

### Batch Web Conversion

```bash
# Convert all TTF files to WOFF2
for f in fonts/*.ttf; do
  fontisan convert "$f" --to woff2 --output "web/$(basename "${f%.ttf}.woff2")"
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
