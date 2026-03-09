---
title: convert
---

# convert

Convert between font formats.

## Usage

```bash
fontisan convert INPUT --to FORMAT [options]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `INPUT` | Input font file |
| `--to FORMAT` | Output format (ttf, otf, woff, woff2) |
| `--output PATH` | Output file path |

## Options

### Opening Options

| Option | Description |
|--------|-------------|
| `--decompose` | Decompose composite glyphs |
| `--convert-curves` | Convert quadratic ↔ cubic curves |
| `--scale-to-1000` | Scale to 1000 UPM |
| `--autohint` | Apply automatic hinting |
| `--generate-unicode` | Generate Unicode from glyph names |
| `--preserve-custom-tables` | Preserve non-standard tables |

### Generating Options

| Option | Description |
|--------|-------------|
| `--hinting-mode MODE` | preserve, auto, none, full |
| `--optimize-tables` | Enable table optimization |
| `--preserve-metadata` | Keep copyright/license info |
| `--strip-metadata` | Remove metadata |
| `--target-format FORMAT` | Collection target format |

### Presets

| Option | Description |
|--------|-------------|
| `--preset NAME` | Use named preset |
| `--show-options` | Show recommended options |

## Presets

| Preset | Description |
|--------|-------------|
| `type1_to_modern` | Type 1 → OpenType |
| `modern_to_type1` | OpenType → Type 1 |
| `web_optimized` | Any → WOFF2 |
| `archive_to_modern` | Collection → OTF |

## Examples

### Basic Conversion

```bash
# TTF to OTF
fontisan convert input.ttf --to otf --output output.otf

# OTF to WOFF2
fontisan convert input.otf --to woff2 --output output.woff2
```

### With Options

```bash
# Convert with autohint
fontisan convert input.ttf --to otf --autohint --output output.otf

# Convert with curve conversion
fontisan convert input.ttf --to otf --convert-curves --output output.otf
```

### Using Presets

```bash
# Type 1 to modern
fontisan convert font.pfb --to otf --preset type1_to_modern --output font.otf

# Web optimized
fontisan convert font.otf --to woff2 --preset web_optimized --output font.woff2
```

### Show Options

```bash
# See what options will be used
fontisan convert input.ttf --to otf --show-options
```

## Batch Conversion

```bash
# Convert all TTF files
for f in *.ttf; do
  fontisan convert "$f" --to woff2 --output "${f%.ttf}.woff2"
done
```
