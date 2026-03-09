# WOFF/WOFF2 Formats

Fontisan supports the Web Open Font Format (WOFF and WOFF2).

## Overview

WOFF and WOFF2 are web font formats optimized for use on websites:

- **WOFF** - Compressed version of TrueType/OpenType with metadata support
- **WOFF2** - Improved compression using Brotli algorithm (typically 30% smaller than WOFF)

## Converting to WOFF

```ruby
require 'fontisan'

# Convert to WOFF
Fontisan.convert('font.ttf', output_format: :woff)

# Convert to WOFF2 (recommended for web)
Fontisan.convert('font.ttf', output_format: :woff2)
```

## Metadata

WOFF files can contain extended metadata:

```ruby
# Add metadata when converting
Fontisan.convert('font.ttf',
  output_format: :woff2,
  metadata: {
    unique_id: 'my-font-1.0',
    license: 'OFL',
    license_url: 'https://scripts.sil.org/OFL',
    description: 'My custom font'
  }
)
```

## Extracting from WOFF

```ruby
# Extract original font from WOFF
Fontisan.convert('font.woff', output_format: :ttf)
Fontisan.convert('font.woff2', output_format: :otf)
```

## Compression Comparison

| Format | Size (relative) |
|--------|----------------|
| TTF/OTF | 100% |
| WOFF | ~70% |
| WOFF2 | ~50% |

## Related

- [Font Conversion](/guide/conversion) - General conversion guide
