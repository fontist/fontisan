---
title: SfntFont
---

# SfntFont

Base class for TrueType and OpenType fonts.

## Overview

`Fontisan::SfntFont` is the base class for sfnt-based fonts (TTF, OTF, WOFF, WOFF2).

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `tables` | Hash | Font tables by tag |
| `glyphs` | GlyphAccessor | Glyph access object |
| `family_name` | String | Font family name |
| `style` | String | Font style |
| `version` | String | Font version |

## Methods

### table(tag)

Access a specific table.

```ruby
head = font.table('head')
name = font.table('name')
```

### glyph_name(id)

Get glyph name by ID.

```ruby
name = font.glyph_name(42)
```

### glyph_count

Get total glyph count.

```ruby
count = font.glyph_count
```

## See Also

- [FontLoader](/api/font-loader)
- [Type1Font](/api/type1-font)
