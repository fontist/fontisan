---
title: tables
---

# tables

Show font table information.

## Quick Reference

```bash
fontisan tables <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--detail` | Show detailed table info |
| `--checksums` | Include checksums |

## Output

Lists all tables in the font with:
- Table tag (4-character identifier)
- Checksum
- Offset
- Length

## Examples

```bash
# List all tables
fontisan tables font.ttf

# With checksums
fontisan tables font.ttf --checksums

# Detailed information
fontisan tables font.ttf --detail

# JSON output
fontisan tables font.ttf --format json
```

## Sample Output

```
Tag    Checksum    Offset    Length
-----  ----------  --------  --------
head   0x12345678  0         54
hhea   0x23456789  54        36
maxp   0x3456789A  90        32
OS/2   0x456789AB  122       96
name   0x56789ABC  218       1024
cmap   0x6789ABCD  1242      2048
...
```

## Common Tables

| Tag | Name | Purpose |
|-----|------|---------|
| `head` | Font Header | Global font info |
| `hhea` | Horizontal Header | Horizontal metrics |
| `maxp` | Maximum Profile | Font requirements |
| `OS/2` | OS/2 | Windows metrics |
| `name` | Naming | Font names/strings |
| `cmap` | Character Map | Unicode to glyph mapping |
| `glyf` | Glyph Data | TrueType outlines |
| `loca` | Location | Glyph offsets |
| `CFF ` | CFF | Compact Font Format |
| `post` | PostScript | PostScript names |
| `GPOS` | Glyph Positioning | OpenType positioning |
| `GSUB` | Glyph Substitution | OpenType substitution |
| `fvar` | Font Variations | Variable font axes |
| `gvar` | Glyph Variations | Glyph deltas |
| `COLR` | Color Layers | Color font layers |
| `CPAL` | Color Palettes | Color font palettes |

## Detailed Documentation

For table access via the Ruby API, see the [SfntFont API](/api/sfnt-font).
