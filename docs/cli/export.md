---
title: export
---

# export

Export font data to various formats for analysis, debugging, or conversion.

## Quick Reference

```bash
fontisan export <font> --format <format> [options]
```

## Export Formats

| Format | Description | Use Case |
|--------|-------------|----------|
| `ttx` | XML-based TTX format | Debugging, inspection |
| `svg` | SVG font | Web graphics |
| `json` | JSON representation | Data processing |
| `yaml` | YAML representation | Human-readable output |

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Export format (ttx, svg, json, yaml) |
| `--output FILE` | Output file path |
| `--tables LIST` | Export specific tables only (comma-separated) |
| `--pretty` | Pretty-print output (JSON, YAML) |
| `--glyphs` | Include glyph outlines (SVG) |

## Examples

### Export to TTX

TTX is an XML representation of font tables, useful for debugging and inspection.

```bash
# Export entire font
fontisan export font.ttf --format ttx --output font.ttx

# Export specific tables
fontisan export font.ttf --format ttx --tables head,name,cmap --output partial.ttx

# Export single table
fontisan export font.ttf --format ttx --tables glyf --output glyf.ttx
```

### Export to SVG

```bash
# Export as SVG font
fontisan export font.ttf --format svg --output font.svg

# Include all glyphs
fontisan export font.ttf --format svg --glyphs --output font-glyphs.svg
```

### Export to JSON/YAML

```bash
# JSON output
fontisan export font.ttf --format json --output font.json

# Pretty-printed JSON
fontisan export font.ttf --format json --pretty --output font-pretty.json

# YAML output
fontisan export font.ttf --format yaml --output font.yaml
```

## TTX Format

TTX is Adobe's XML format for font tables. It's human-readable and diffable.

### Sample TTX Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ttFont sfntVersion="OTTO" ttLibVersion="4.0">
  <head>
    <tableVersion value="1.0"/>
    <fontRevision value="3.046"/>
    <checkSumAdjustment value="0"/>
    <unitsPerEm value="1000"/>
    ...
  </head>
  <name>
    <namerecord nameID="1" platformID="3" platEncID="1" langID="0x409">
      Source Sans 3
    </namerecord>
    ...
  </name>
</ttFont>
```

## SVG Font Format

SVG fonts define glyphs as SVG paths, usable in web contexts.

### Sample SVG Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg">
  <font id="MyFont" horiz-adv-x="500">
    <font-face font-family="My Font" units-per-em="1000"/>
    <glyph unicode="A" d="M100 0 L200 700 L300 0 Z"/>
    ...
  </font>
</svg>
```

## JSON/YAML Output

Structured output for programmatic access.

### Sample JSON Output

```json
{
  "format": "OpenType",
  "family": "Source Sans 3",
  "style": "Regular",
  "version": "3.046",
  "glyphs": 1024,
  "tables": {
    "head": { "unitsPerEm": 1000, ... },
    "name": { "records": [...] },
    ...
  }
}
```

## Use Cases

### Debug Font Issues

```bash
# Export and search for issues
fontisan export font.ttf --format ttx --output debug.ttx
grep -i "error\|warning" debug.ttx
```

### Compare Fonts

```bash
# Export both fonts
fontisan export font1.ttf --format ttx --output font1.ttx
fontisan export font2.ttf --format ttx --output font2.ttx

# Compare
diff font1.ttx font2.ttx
```

### Extract Font Data

```bash
# Get font metadata as JSON
fontisan export font.ttf --format json | jq '.family, .style, .version'
```

### Create SVG Glyphs

```bash
# Export individual glyphs for web use
fontisan export font.ttf --format svg --glyphs --output glyphs.svg
```

## Related Commands

- [tables](/cli/tables) — List font tables
- [dump-table](/cli/dump-table) — Extract raw table data
- [convert](/cli/convert) — Convert font formats
