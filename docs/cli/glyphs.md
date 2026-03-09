---
title: glyphs
---

# glyphs

List and inspect glyphs in a font.

## Quick Reference

```bash
fontisan glyphs <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--with-unicode` | Include Unicode codepoints |
| `--with-bbox` | Include bounding boxes |
| `--filter PATTERN` | Filter by glyph name pattern |

## Output

Lists all glyphs with:
- Glyph ID (GID)
- Glyph name
- Unicode codepoint (if mapped)
- Bounding box (optional)

## Examples

```bash
# List all glyphs
fontisan glyphs font.ttf

# With Unicode codepoints
fontisan glyphs font.ttf --with-unicode

# With bounding boxes
fontisan glyphs font.ttf --with-bbox

# Filter by name pattern
fontisan glyphs font.ttf --filter "uni*"

# JSON output for processing
fontisan glyphs font.ttf --format json > glyphs.json
```

## Sample Output

```
GID   Name              Unicode    Bounding Box
----  ----------------  ---------  ---------------
0     .notdef           -          (0, 0, 500, 700)
1     space             U+0020     (0, 0, 0, 0)
2     exclam            U+0021     (100, 0, 200, 700)
3     quotedbl          U+0022     (80, 450, 420, 700)
4     numbersign        U+0023     (30, 0, 470, 700)
...
```

## Use Cases

### Count Glyphs

```bash
fontisan glyphs font.ttf | wc -l
```

### Find Specific Glyphs

```bash
# Find ligatures
fontisan glyphs font.ttf | grep "_"

# Find small caps
fontisan glyphs font.ttf | grep "\.sc"
```

### Export Glyph List

```bash
fontisan glyphs font.ttf --format json --with-unicode > glyph-map.json
```

## Detailed Documentation

For glyph access via the Ruby API, see the [GlyphAccessor API](/api/models/glyph-accessor).
