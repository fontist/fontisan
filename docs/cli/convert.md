---
title: convert
---

# convert

Convert individual fonts between different formats.

::: tip For Collection Formats
Use [pack/unpack](/cli/pack) to work with TTC, OTC, and dfont collections. The convert command is for individual font files only.
:::

## Quick Reference

```bash
fontisan convert <input> --to <format> [options]
```

## Supported Formats

These are individual font formats that can be converted:

| Format | Read | Write | Description |
|--------|:----:|:-----:|-------------|
| TTF | ✅ | ✅ | TrueType (glyf outlines) |
| OTF | ✅ | ✅ | OpenType (CFF outlines) |
| WOFF | ✅ | ✅ | Web Open Font Format |
| WOFF2 | ✅ | ✅ | Web Open Font Format 2 |
| PFB/PFA | ✅ | — | Adobe Type 1 (read for conversion) |

## Options

| Option | Description |
|--------|-------------|
| `--to FORMAT` | Target format (ttf, otf, woff, woff2) |
| `--output FILE` | Output file path |
| `--optimize` | Enable outline optimization |
| `--flatten` | Flatten composite glyphs |

## Common Workflows

### Convert for Web

```bash
# TTF to WOFF2 (recommended for modern browsers)
fontisan convert font.ttf --to woff2 --output font.woff2

# OTF to WOFF (broader compatibility)
fontisan convert font.otf --to woff --output font.woff
```

### Convert Between Outline Formats

```bash
# TrueType to OpenType (glyf → CFF)
fontisan convert font.ttf --to otf --output font.otf

# OpenType to TrueType (CFF → glyf)
fontisan convert font.otf --to ttf --output font.ttf
```

### Convert Legacy Type 1 Fonts

```bash
# Type 1 to OpenType
fontisan convert font.pfb --to otf --output font.otf
```

## Working with Collections

Collection formats (TTC, OTC, dfont) contain multiple fonts. To convert fonts from a collection:

```bash
# Step 1: Extract fonts from collection
fontisan unpack family.ttc --output-dir ./extracted

# Step 2: Convert each font
fontisan convert ./extracted/Font-Regular.ttf --to woff2 --output Font-Regular.woff2
fontisan convert ./extracted/Font-Bold.ttf --to woff2 --output Font-Bold.woff2

# Or extract and convert in one step:
fontisan unpack family.ttc --output-dir ./web --format woff2
```

## Detailed Documentation

For comprehensive documentation including curve conversion, hint handling, and advanced options, see the [convert command guide](/guide/cli/convert).
