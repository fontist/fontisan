---
title: ls
---

# ls

List fonts in a collection.

## Quick Reference

```bash
fontisan ls <collection> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--verbose` | Show detailed information |

## Supported Collections

- TTC (TrueType Collection)
- OTC (OpenType Collection)
- dfont (Apple Data Fork Font)

## Examples

```bash
# List fonts in a TTC
fontisan ls fonts.ttc

# List fonts in a dfont
fontisan ls fonts.dfont

# JSON output
fontisan ls fonts.ttc --format json

# Verbose output
fontisan ls fonts.ttc --verbose
```

## Sample Output

```
Collection: fonts.ttc
Fonts: 4

0. Noto Serif CJK JP
   PostScript: NotoSerifCJKJP-Regular
   Format: OpenType
   Glyphs: 65,535

1. Noto Serif CJK KR
   PostScript: NotoSerifCJKKR-Regular
   Format: OpenType
   Glyphs: 65,535

2. Noto Serif CJK SC
   PostScript: NotoSerifCJKSC-Regular
   Format: OpenType
   Glyphs: 65,535

3. Noto Serif CJK TC
   PostScript: NotoSerifCJKTC-Regular
   Format: OpenType
   Glyphs: 65,535
```

## Use Cases

### Count Fonts in Collection

```bash
fontisan ls fonts.ttc | grep -c "PostScript"
```

### Get Font Index for Extraction

```bash
# Find the index of a specific font
fontisan ls fonts.ttc | grep -n "Bold"
```

### Extract Collection Info to JSON

```bash
fontisan ls fonts.ttc --format json > collection-info.json
```

## Related Commands

- [pack/unpack](/cli/pack) — Create and extract collections
- [info](/cli/info) — Get detailed font information
