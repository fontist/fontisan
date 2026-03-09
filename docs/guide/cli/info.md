---
title: info
---

# info

Get font information.

## Usage

```bash
fontisan info FONT [options]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `FONT` | Font file to analyze |

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--tables` | Show table information |
| `--glyphs` | Show glyph information |
| `--unicode` | Show Unicode coverage |
| `--features` | Show OpenType features |
| `--verbose` | Detailed output |

## Examples

### Basic Info

```bash
fontisan info font.ttf

# Font: font.ttf
# Format: TrueType
# Family: Example
# Style: Regular
# Version: 1.000
# Glyphs: 268
# Tables: 14
```

### Table Information

```bash
fontisan info font.ttf --tables

# Tables:
#   head - Font header (54 bytes)
#   hhea - Horizontal header (36 bytes)
#   maxp - Maximum profile (32 bytes)
#   name - Naming table (2456 bytes)
#   cmap - Character mapping (1234 bytes)
#   ...
```

### Unicode Coverage

```bash
fontisan info font.ttf --unicode

# Unicode Coverage:
#   Basic Latin (U+0000-U+007F)
#   Latin-1 Supplement (U+0080-U+00FF)
#   Latin Extended-A (U+0100-U+017F)
#   ...
```

### OpenType Features

```bash
fontisan info font.ttf --features

# OpenType Features:
#   GSUB:
#     liga - Ligatures
#     kern - Kerning
#   GPOS:
#     kern - Kerning
#     mark - Mark positioning
```

### YAML Output

```bash
fontisan info font.ttf --format yaml

# family: Example
# style: Regular
# version: 1.000
# glyphs: 268
# tables:
#   head: 54
#   hhea: 36
#   ...
```

### JSON Output

```bash
fontisan info font.ttf --format json

# {
#   "family": "Example",
#   "style": "Regular",
#   "version": "1.000",
#   "glyphs": 268
# }
```

## Variable Font Info

```bash
fontisan info variable.ttf

# Variable Font Axes: 2
#   wght (Weight): 100 - 900, default: 400
#   wdth (Width): 75 - 125, default: 100
#
# Named Instances: 6
#   0: Thin (wght=100)
#   1: Light (wght=300)
#   2: Regular (wght=400)
#   ...
```

## Collection Info

```bash
fontisan info fonts.ttc

# Collection: fonts.ttc
# Format: TTC
# Fonts: 4
# Size: 256 KB
#
# Shared Tables: 4
# Space Saved: 45%
```
