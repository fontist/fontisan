---
title: info
---

# info

Get comprehensive font information.

## Quick Reference

```bash
fontisan info <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--verbose` | Show all available information |
| `--tables` | Include table listing |
| `--features` | Include OpenType features |

## Output

Shows comprehensive font metadata:
- Family and style names
- Version and copyright
- PostScript name
- Format (TrueType, OpenType, etc.)
- Glyph count
- Table count
- Unicode ranges
- Variable font axes (if applicable)

## Examples

```bash
# Basic info
fontisan info font.ttf

# Verbose output
fontisan info font.ttf --verbose

# Include tables
fontisan info font.ttf --tables

# JSON output
fontisan info font.ttf --format json
```

## Sample Output

```
Font: SourceSans3-Regular.otf
Format: OpenType (CFF)
Family: Source Sans 3
Style: Regular
PostScript: SourceSans3-Regular
Version: 3.046
Copyright: Copyright 2023 Adobe

Glyphs: 1,024
Tables: 18
Characters: 892

Unicode Ranges:
  Basic Latin (95)
  Latin-1 Supplement (96)
  Latin Extended-A (128)
  Greek and Coptic (72)

Features: 24
  liga, dlig, kern, mark, mkmk, ...
```

## Use Cases

### Get Family Name

```bash
fontisan info font.ttf --format json | jq '.family_name'
```

### Check Font Format

```bash
fontisan info font.ttf --format json | jq '.format'
```

### Compare Fonts

```bash
diff <(fontisan info font1.ttf) <(fontisan info font2.ttf)
```

### Batch Process Fonts

```bash
for font in *.ttf; do
  echo "=== $font ==="
  fontisan info "$font" --format yaml
done
```

## Related Commands

- [tables](/cli/tables) — Detailed table information
- [glyphs](/cli/glyphs) — List all glyphs
- [features](/cli/features) — List OpenType features
- [variable](/cli/variable) — Variable font details
