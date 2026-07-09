---
title: subset
---

# subset

Create font subsets with reduced character sets.

## Quick Reference

```bash
fontisan subset <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--chars TEXT` | Characters to include |
| `--file FILE` | File containing characters |
| `--unicodes RANGE` | Unicode ranges (`"U+0000-007F"`) |
| `--glyphs LIST` | Glyph names/IDs |
| `--output FILE` | Output file path |
| `--format FORMAT` | Output format (`ttf`, `woff`, `woff2`, …) |
| `--profile PROFILE` | Subsetting profile (default: `pdf`) |
| `--retain-gids` | Preserve original glyph IDs |

## Profiles

| Profile | Tables included | Use case |
|---------|-----------------|----------|
| `pdf` | core + glyf/loca | PDF embedding (smallest) |
| `web` | core + glyf/loca + GSUB/GPOS + **CBDT/CBLC** | Web fonts that retain color-emoji bitmaps |
| `minimal` | core only | Smallest valid font |
| `full` | every standard table | Lossless re-export |

The `web` profile is the one to reach for when the subset must still render color emoji in a browser: it preserves the CBDT (bitmap data) and CBLC (bitmap location) tables, and the paired subsetter rewrites them to keep only the bitmaps for the retained glyphs.

## Examples

```bash
# Subset to specific characters
fontisan subset font.ttf --chars "ABCDEF" --output subset.ttf

# Web subset that retains color-emoji bitmaps
fontisan subset NotoColorEmoji.ttf \
  --chars "😀😁😂🤣😊" \
  --profile web \
  --format woff2 \
  --output emoji.woff2

# PDF embedding profile (drops CBDT/CBLC, smaller output)
fontisan subset font.ttf --chars "ABC" --profile pdf --output pdf-subset.ttf
```

## Detailed Documentation

For comprehensive documentation including unicode ranges, profile selection, and CBDT/CBLC behavior, see the [subset command guide](/guide/cli/subset).
