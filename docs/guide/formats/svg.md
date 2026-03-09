---
title: SVG Fonts
---

# SVG Fonts

SVG fonts define glyphs using SVG graphics.

## Overview

- **Format**: SVG document
- **Features**: Full SVG capabilities
- **Use Case**: Specialized applications

## Structure

SVG fonts are SVG documents with font definitions:

```xml
<svg>
  <font>
    <font-face font-family="MyFont"/>
    <glyph unicode="A" d="M0 0 L100 0..."/>
  </font>
</svg>
```

## Loading

```ruby
font = Fontisan::FontLoader.load('font.svg')

# Access glyphs
font.glyphs.each do |glyph|
  puts glyph.unicode
  puts glyph.path_data
end
```

## Creating

SVG fonts can be created manually or with tools:

```ruby
# Export to SVG
Fontisan::FontWriter.write(font, 'output.svg', format: :svg)
```

## Converting

### SVG to TTF

```bash
fontisan convert font.svg --to ttf --output font.ttf
```

### SVG to OTF

```bash
fontisan convert font.svg --to otf --output font.otf
```

### From other formats

```bash
fontisan convert font.ttf --to svg --output font.svg
```

## Limitations

- **No hinting** — SVG has no hint support
- **Large files** — XML overhead
- **Limited layout** — No GSUB/GPOS
- **Variable support** — No variable fonts

## SVG vs COLR/CPAL

| Feature | SVG Font | COLR/CPAL |
|---------|----------|-----------|
| File size | Large | Small |
| Effects | Full | Limited |
| Browser support | Good | Good |
| Variable fonts | No | Yes |
| Performance | Slow | Fast |

## When to Use

- **SVG workflows** — Integration with SVG graphics
- **Special effects** — Complex visual effects
- **Legacy content** — Existing SVG fonts

## Modern Alternatives

For most uses, prefer:
- **COLR/CPAL** — Color fonts
- **WOFF2** — Web delivery
- **OTF/TTF** — General use
