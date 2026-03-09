---
title: Conversion Overview
---

# Conversion Overview

Fontisan's conversion system is based on the TypeTool 3 manual's recommended options for different font format conversions. The system provides:

- **Type-safe option validation** — Catch errors before conversion
- **Format-specific defaults** — Recommended options per conversion type
- **Named presets** — Common workflows pre-configured
- **Fine-grained control** — Override any option when needed

## Quick Start

### Using the CLI

```bash
# Basic conversion
fontisan convert input.ttf --to otf --output output.otf

# Show recommended options
fontisan convert input.ttf --to otf --show-options

# Use a preset
fontisan convert font.pfb --to otf --preset type1_to_modern --output output.otf

# Custom options
fontisan convert input.ttf --to otf --autohint --hinting-mode auto --output output.otf
```

### Using the API

```ruby
require 'fontisan'

# Get recommended options
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)

# Use a preset
options = Fontisan::ConversionOptions.from_preset(:web_optimized)

# Build custom options
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: { autohint: true, convert_curves: true },
  generating: { hinting_mode: "auto" }
)

# Convert with options
converter = Fontisan::Converters::OutlineConverter.new
tables = converter.convert(font, options: options)
```

## Supported Formats

### Input Formats

| Format | Description | Extensions |
|--------|-------------|------------|
| TTF | TrueType Font | .ttf |
| OTF | OpenType/CFF Font | .otf |
| Type 1 | Adobe Type 1 Font | .pfb, .pfa |
| TTC | TrueType Collection | .ttc |
| OTC | OpenType Collection | .otc |
| dfont | Apple Data Fork Font | .dfont |
| WOFF | Web Open Font Format | .woff |
| WOFF2 | Web Open Font Format 2 | .woff2 |
| SVG | SVG Font | .svg |

### Output Formats

All input formats can be converted to: **TTF, OTF, WOFF, WOFF2**

Collections (TTC, OTC, dfont) can be converted between each other.

## Conversion Guides

- [TTF ↔ OTF](/guide/conversion/ttf-otf) — TrueType and OpenType conversion
- [Type 1 → Modern](/guide/conversion/type1) — Converting legacy Type 1 fonts
- [Web Formats](/guide/conversion/web) — WOFF and WOFF2 optimization
- [Collections](/guide/conversion/collections) — TTC, OTC, and dfont handling
- [Curve Conversion](/guide/conversion/curves) — Quadratic ↔ Cubic curves
- [Options Reference](/guide/conversion/options) — Complete option documentation

## Presets

Fontisan includes presets for common workflows:

| Preset | Description |
|--------|-------------|
| `type1_to_modern` | Type 1 → OpenType for modern use |
| `modern_to_type1` | OpenType → Type 1 for legacy systems |
| `web_optimized` | Any → WOFF2 for web delivery |
| `archive_to_modern` | Collection → Individual OTF files |

```ruby
# Using presets
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
```

## Hinting Modes

Control hinting behavior with `--hinting-mode`:

| Mode | Description | Use Case |
|------|-------------|----------|
| `preserve` | Keep original hints | Same-format conversions |
| `auto` | Apply automatic hinting | Cross-format conversions |
| `none` | Remove all hints | Maximum file size reduction |
| `full` | Full hint conversion | Print applications |

## Best Practices

1. **Use presets when possible** — Presets are optimized for common workflows
2. **Show options first** — Use `--show-options` to understand what will be applied
3. **Test conversions** — Always verify output fonts in target applications
4. **Preserve metadata** — Keep copyright and license information intact

## Troubleshooting

### Conversion Fails

```bash
# Check if source file is valid
fontisan info font.ttf

# Validate source font
fontisan validate font.ttf

# Try with verbose flag
fontisan convert font.ttf --to otf --verbose
```

### Output Font Too Large

```bash
# Enable optimization
fontisan convert font.ttf --to otf --optimize-tables

# Remove hinting
fontisan convert font.ttf --to otf --hinting-mode none

# Use web font format
fontisan convert font.ttf --to woff2
```

### Poor Rendering Quality

```bash
# Use autohinting
fontisan convert font.ttf --to otf --autohint --hinting-mode auto

# Preserve original hints
fontisan convert font.ttf --to otf --hinting-mode preserve
```
