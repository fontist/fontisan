---
title: subset
---

# subset

Create font subsets.

## Usage

```bash
fontisan subset FONT [options]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `FONT` | Input font file |

## Options

| Option | Description |
|--------|-------------|
| `--chars TEXT` | Characters to include |
| `--chars-file PATH` | File with characters |
| `--unicodes RANGE` | Unicode ranges |
| `--glyphs LIST` | Glyph names/IDs |
| `--output PATH` | Output file |
| `--output-format FORMAT` | Output format |
| `--retain-gids` | Retain glyph IDs |

## Examples

### By Characters

```bash
# Subset to specific characters
fontisan subset font.ttf --chars "ABCDEFabcdef0123456789" --output subset.ttf

# Subset to ASCII
fontisan subset font.ttf --chars "$(printf '%s' {a..z} {A..Z} {0..9})" --output ascii.ttf
```

### By Unicode Range

```bash
# Basic Latin only
fontisan subset font.ttf --unicodes "U+0000-007F" --output basic-latin.ttf

# Latin + Latin-1
fontisan subset font.ttf --unicodes "U+0000-00FF" --output latin1.ttf

# Multiple ranges
fontisan subset font.ttf --unicodes "U+0000-007F,U+00A0-00FF" --output extended.ttf
```

### By Glyph Names

```bash
# Specific glyphs
fontisan subset font.ttf --glyphs "A,B,C,a,b,c,zero,one,two" --output subset.ttf
```

### From File

```bash
# Read characters from file
echo "Hello World" > chars.txt
fontisan subset font.ttf --chars-file chars.txt --output subset.ttf
```

### Retain Glyph IDs

```bash
# Keep original glyph IDs
fontisan subset font.ttf --chars "ABC" --retain-gids --output subset.ttf
```

### With Format Conversion

```bash
# Subset and convert to WOFF2
fontisan subset font.ttf --chars "ABC" --output-format woff2 --output subset.woff2
```

## Subsetting Strategies

### Web Font Optimization

```bash
# Subset to page content
fontisan subset font.ttf --chars "$(cat content.html)" --output web-font.woff2
```

### Latin Only

```bash
# Standard Latin subset
fontisan subset font.ttf --unicodes "U+0000-024F,U+1E00-1EFF" --output latin.woff2
```

### Character Set Presets

```bash
# ASCII
fontisan subset font.ttf --unicodes "U+0000-007F" --output ascii.ttf

# Basic Multilingual Plane (BMP)
fontisan subset font.ttf --unicodes "U+0000-FFFF" --output bmp.ttf
```

## Notes

- Subsetting removes unused glyphs and tables
- CFF fonts may require special handling
- Variable fonts are subset while preserving variation
- OpenType features are preserved for included glyphs
