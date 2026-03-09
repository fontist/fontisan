---
title: Options Reference
---

# Options Reference

Complete reference for Fontisan's conversion options.

## Opening Options

Opening options control how the source font is read and processed.

| Option | Type | Description | Use Case |
|--------|------|-------------|----------|
| `decompose_composites` | Boolean | Decompose composite glyphs into simple glyphs | Target format doesn't support composites |
| `convert_curves` | Boolean | Convert curve types during conversion | Quadratic ↔ Cubic conversion |
| `scale_to_1000` | Boolean | Scale UPM to 1000 | Type 1 → OTF conversions |
| `scale_from_1000` | Boolean | Scale from 1000 UPM | OTF → TTF conversions |
| `autohint` | Boolean | Auto-hint the font | Source lacks hints or incompatible |
| `generate_unicode` | Boolean | Generate Unicode from glyph names | Type 1 conversions |
| `store_custom_tables` | Boolean | Preserve non-standard tables | Custom tables need preservation |
| `store_native_hinting` | Boolean | Preserve native hinting data | Hints for source format |
| `interpret_ot` | Boolean | Interpret OpenType layout features | GSUB/GPOS processing needed |
| `read_all_records` | Boolean | Load all font dictionary records | Type 1 with custom data |
| `preserve_encoding` | String | Preserve character encoding | Custom encoding required |

## Generating Options

Generating options control how the output font is written.

| Option | Type | Description | Use Case |
|--------|------|-------------|----------|
| `write_pfm` | Boolean | Write PFM file | Type 1 output |
| `write_afm` | Boolean | Write AFM file | Type 1 output |
| `write_inf` | Boolean | Write INF file | Type 1 output |
| `select_encoding_automatically` | Boolean | Auto-select encoding | Type 1 output |
| `hinting_mode` | String | Hint mode: preserve, auto, none, full | Control hinting |
| `decompose_on_output` | Boolean | Decompose composites in output | Target doesn't support composites |
| `write_custom_tables` | Boolean | Write custom tables | Preserve non-standard tables |
| `optimize_tables` | Boolean | Enable table optimization | Reduce file size |
| `reencode_first_256` | Boolean | Reencode first 256 glyphs | Type 1 output |
| `encoding_vector` | String | Custom encoding vector | Type 1 output |
| `compression` | String | Compression: zlib, brotli, none | Web font output |
| `transform_tables` | Boolean | Transform tables for output | Format-specific |
| `preserve_metadata` | Boolean | Preserve copyright/license metadata | Maintain metadata |
| `strip_metadata` | Boolean | Remove metadata | Reduce file size |
| `target_format` | String | Collection target format | Collection conversions |
| `curve_tolerance` | Float | Curve approximation tolerance | OTF → TTF |

## CLI Option Mapping

### Opening Options

```bash
# Decompose composite glyphs
--decompose           # Enable decomposition
--no-decompose        # Preserve composite glyphs

# Curve conversion
--convert-curves      # Convert quadratic ↔ cubic

# UPM scaling
--scale-to-1000       # Scale to 1000 UPM
--scale-from-1000     # Scale from 1000 UPM

# Hinting
--autohint            # Apply automatic hinting

# Unicode and encoding
--generate-unicode    # Generate Unicode from glyph names
--preserve-encoding   # Preserve character encoding

# Table handling
--preserve-custom-tables  # Preserve non-standard tables
--interpret-ot            # Interpret OpenType tables
```

### Generating Options

```bash
# Type 1 metrics files
--write-pfm           # Generate PFM file
--write-afm           # Generate AFM file
--write-inf           # Generate INF file

# Encoding
--auto-encoding        # Auto-detect encoding
--encoding VECTOR      # Use specific encoding vector

# Hinting
--hinting-mode MODE   # preserve|auto|none|full

# Optimization
--optimize-tables      # Enable optimization
--no-optimization      # Disable optimization

# Metadata
--preserve-metadata    # Preserve copyright/license
--strip-metadata       # Remove metadata

# Collections
--target-format FORMAT # ttf|otf|preserve

# Curves
--curve-tolerance N   # Approximation tolerance (0.1-2.0)
```

### Preset Option

```bash
--preset NAME          # type1_to_modern, web_optimized, etc.
```

## Hinting Modes

| Mode | Description | Best For |
|------|-------------|----------|
| `preserve` | Keep original hints | Same-format, compatible hints |
| `auto` | Apply automatic hinting | Cross-format, missing hints |
| `none` | Remove all hints | Web fonts, smallest size |
| `full` | Full hint conversion | Print, maximum quality |

### preserve

```ruby
generating: { hinting_mode: "preserve" }
```

- Works best when source and target formats share hinting systems
- TTF → TTF: TrueType instructions preserved
- OTF → OTF: PostScript hints preserved
- Cross-format: May result in lost hints

### auto

```ruby
generating: { hinting_mode: "auto" }
```

- TTF → OTF: Autohinting applied to CFF output
- OTF → TTF: Autohinting applied to TrueType output
- Type 1 → Modern: Autohinting based on outlines

### none

```ruby
generating: { hinting_mode: "none" }
```

- Smallest file size
- No rendering optimizations
- Useful when file size matters more than rendering

### full

```ruby
generating: { hinting_mode: "full" }
```

- Attempts to preserve all hint information
- May generate larger files
- Best quality for print applications

## Presets

### type1_to_modern

Type 1 fonts to modern OpenType format.

```ruby
Fontisan::ConversionOptions.from_preset(:type1_to_modern)
# From: :type1, To: :otf
# opening: { generate_unicode: true, decompose_composites: false }
# generating: { hinting_mode: "preserve", decompose_on_output: true }
```

### modern_to_type1

Modern fonts to Type 1 format.

```ruby
Fontisan::ConversionOptions.from_preset(:modern_to_type1)
# From: :otf, To: :type1
# opening: { convert_curves: true, scale_to_1000: true,
#           autohint: true }
# generating: { write_pfm: true, write_afm: true, write_inf: true }
```

### web_optimized

Fonts optimized for web delivery.

```ruby
Fontisan::ConversionOptions.from_preset(:web_optimized)
# From: :otf, To: :woff2
# opening: {}
# generating: { compression: "brotli", transform_tables: true,
#              optimize_tables: true, preserve_metadata: true }
```

### archive_to_modern

Collection extraction and modernization.

```ruby
Fontisan::ConversionOptions.from_preset(:archive_to_modern)
# From: :ttc, To: :otf
# opening: { convert_curves: true, decompose_composites: false }
# generating: { target_format: "otf", hinting_mode: "preserve" }
```

## Using Options

### CLI

```bash
# Show options before conversion
fontisan convert font.ttf --to otf --show-options

# Use preset
fontisan convert font.pfb --to otf --preset type1_to_modern

# Custom options
fontisan convert font.ttf --to otf \
  --autohint \
  --hinting-mode auto \
  --optimize-tables \
  --output font.otf
```

### API

```ruby
# Get recommended options
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)

# Use preset
options = Fontisan::ConversionOptions.from_preset(:web_optimized)

# Build custom options
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: { autohint: true, convert_curves: true },
  generating: { hinting_mode: "auto", optimize_tables: true }
)

# Convert with options
converter = Fontisan::Converters::OutlineConverter.new
tables = converter.convert(font, options: options)
```
