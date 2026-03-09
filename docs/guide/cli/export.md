---
title: export
---

# export

Export font data to various formats.

## Usage

```bash
fontisan export FONT [options]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `FONT` | Input font file |

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Export format (ttx, svg, ufo) |
| `--output PATH` | Output file/directory |
| `--tables LIST` | Export specific tables |

## Export Formats

| Format | Description |
|--------|-------------|
| `ttx` | XML dump of font tables |
| `svg` | SVG font format |
| `ufo` | Unified Font Object |

## Examples

### Export to TTX

```bash
# Export all tables
fontisan export font.ttf --format ttx --output font.ttx

# Export specific tables
fontisan export font.ttf --format ttx --tables head,name,cmap --output font-partial.ttx
```

### Export to SVG

```bash
# Create SVG font
fontisan export font.ttf --format svg --output font.svg
```

### Export to UFO

```bash
# Create UFO package
fontisan export font.ttf --format ufo --output font.ufo
```

## TTX Format

TTX is an XML representation of font tables:

```xml
<?xml version="1.0"?>
<ttFont>
  <head>
    <tableVersion value="1.0"/>
    <fontRevision value="1.0"/>
    <unitsPerEm value="1000"/>
    ...
  </head>
  <name>
    <namerecord nameID="1">Example</namerecord>
    ...
  </name>
</ttFont>
```

### Export Specific Tables

```bash
# Just head and name
fontisan export font.ttf --format ttx --tables head,name --output tables.ttx
```

### Compare Tables

```bash
# Export from two fonts
fontisan export font1.ttf --format ttx --tables name --output name1.ttx
fontisan export font2.ttf --format ttx --tables name --output name2.ttx

# Compare
diff name1.ttx name2.ttx
```

## SVG Export

Creates an SVG font file:

```bash
fontisan export font.ttf --format svg --output font.svg
```

Result:
```xml
<svg xmlns="http://www.w3.org/2000/svg">
  <font>
    <font-face font-family="Example"/>
    <glyph unicode="A" d="M0 0 L100 0..."/>
    <glyph unicode="B" d="M0 0 L100 0..."/>
  </font>
</svg>
```

## UFO Export

Creates a UFO (Unified Font Object) package:

```bash
fontisan export font.ttf --format ufo --output font.ufo
```

Structure:
```
font.ufo/
├── fontinfo.plist
├── glyphs/
│   ├── A.glif
│   ├── B.glif
│   └── ...
├── glyphs.contents
└── metainfo.plist
```
