---
title: WOFF & WOFF2
---

# WOFF & WOFF2

Web Open Font Format (WOFF and WOFF2) are optimized for web delivery.

## Overview

| Format | Compression | Browser Support |
|--------|-------------|-----------------|
| WOFF | zlib | All modern browsers |
| WOFF2 | brotli | Modern browsers |

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
```

## Converting to WOFF2

```bash
# From TTF
fontisan convert font.ttf --to woff2 --output font.woff2

# From OTF
fontisan convert font.otf --to woff2 --output font.woff2

# From Type 1
fontisan convert font.pfb --to woff2 --output font.woff2
```

## API Usage

```ruby
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# generating: { compression: "brotli", transform_tables: true }

Fontisan::FontWriter.write(font, 'font.woff2', options: options)
```

## Compression Options

### brotli (WOFF2)

```ruby
generating: { compression: "brotli" }
```

Best compression ratio.

### zlib (WOFF)

```ruby
generating: { compression: "zlib" }
```

Wide compatibility.

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
2. **Provide WOFF fallback** — For older browsers
3. **Keep original** — For editing
4. **Preserve metadata** — Unless stripping for size
