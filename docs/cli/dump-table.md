---
title: dump-table
---

# dump-table

Extract raw table data from a font.

## Quick Reference

```bash
fontisan dump-table <font> <table-tag> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--output FILE` | Output file (default: stdout) |
| `--hex` | Output as hexadecimal |
| `--json` | Parse and output as JSON |

## Output

Outputs raw binary table data, or parsed data if `--json` is specified.

## Examples

### Raw Binary Output

```bash
# Dump head table to file
fontisan dump-table font.ttf head --output head.bin

# Dump cmap table
fontisan dump-table font.ttf cmap --output cmap.bin
```

### Hexadecimal Output

```bash
# View as hex
fontisan dump-table font.ttf head --hex
```

### Parsed JSON Output

```bash
# Get parsed table data
fontisan dump-table font.ttf head --json

# Extract specific values
fontisan dump-table font.ttf head --json | jq '.unitsPerEm'
```

## Common Tables to Dump

| Table | Contains |
|-------|----------|
| `head` | Font header, units per em, bbox |
| `name` | All naming strings |
| `cmap` | Character to glyph mapping |
| `glyf` | Glyph outlines (TrueType) |
| `CFF ` | Compact font format data |
| `maxp` | Maximum profile |
| `hhea` | Horizontal header |
| `OS/2` | OS/2 metrics |
| `post` | PostScript names |
| `GPOS` | Glyph positioning |
| `GSUB` | Glyph substitution |
| `fvar` | Variation axes |
| `STAT` | Style attributes |

## Use Cases

### Debug Font Issues

```bash
# Check head table values
fontisan dump-table font.ttf head --json
```

### Extract Naming Data

```bash
# Get all name strings
fontisan dump-table font.ttf name --json > names.json
```

### Compare Tables Between Fonts

```bash
# Compare head tables
diff <(fontisan dump-table font1.ttf head --hex) \
     <(fontisan dump-table font2.ttf head --hex)
```

### Backup Table Data

```bash
# Backup critical tables
fontisan dump-table font.ttf head --output backup/head.bin
fontisan dump-table font.ttf name --output backup/name.bin
fontisan dump-table font.ttf cmap --output backup/cmap.bin
```

## Related Commands

- [tables](/cli/tables) — List all tables
- [export](/cli/export) — Export to TTX, SVG, etc.
