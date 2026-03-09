---
title: Glyph
---

# Glyph

Font glyph representation.

## Overview

`Fontisan::Glyph` represents a single glyph.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | Integer | Glyph ID |
| `name` | String | Glyph name |
| `unicode` | Integer | Unicode codepoint |
| `bounds` | Hash | Bounding box |
| `contours` | Array | Outline contours |

## Methods

### outline

Get glyph outline.

```ruby
outline = glyph.outline
outline.contours.each do |contour|
  contour.points.each do |point|
    puts "(#{point.x}, #{point.y})"
  end
end
```

## See Also

- [GlyphAccessor](/api/models/glyph-accessor)
