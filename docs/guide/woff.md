# WOFF/WOFF2 Formats

Fontisan supports the Web Open Font Format (WOFF and WOFF2).

## Overview

WOFF and WOFF2 are web font formats optimized for use on websites:

- **WOFF** - Compressed version of TrueType/OpenType with metadata support
- **WOFF2** - Improved compression using Brotli algorithm (typically 30% smaller than WOFF)

The format you pick (`--to woff` vs `--to woff2`) **is** the algorithm
choice: WOFF mandates zlib, WOFF2 mandates Brotli. Each format exposes
its algorithm's parameters (level, quality, transform) rather than
offering a separate algorithm selector.

## Converting to WOFF

```ruby
require 'fontisan'

# Convert to WOFF (max zlib for legacy browser reach)
Fontisan.convert('font.ttf', to: :woff, output: 'font.woff', zlib_level: 9)

# Convert to WOFF2 (recommended for modern browsers)
Fontisan.convert('font.ttf', to: :woff2, output: 'font.woff2',
                 brotli_quality: 11, transform_tables: true)
```

## Metadata

WOFF files can carry an extended metadata block:

```ruby
# Add WOFF metadata when converting
Fontisan.convert('font.ttf',
  to: :woff,
  output: 'font.woff',
  metadata_xml: '<metadata>...</metadata>')
```

## Extracting from WOFF

```ruby
# Extract original font from WOFF
Fontisan.convert('font.woff', to: :ttf, output: 'font.ttf')
Fontisan.convert('font.woff2', to: :otf, output: 'font.otf')
```

## Compression Comparison

| Format | Size (relative) |
|--------|----------------|
| TTF/OTF | 100% |
| WOFF | ~70% |
| WOFF2 | ~50% |

## Related

- [Web Font Formats](/guide/conversion/web) - Detailed WOFF/WOFF2 guide with all compression knobs
- [Font Conversion](/guide/conversion/) - General conversion guide
