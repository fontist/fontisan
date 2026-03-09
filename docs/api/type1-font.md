---
title: Type1Font
---

# Type1Font

Adobe Type 1 font handler.

## Overview

`Fontisan::Type1Font` handles Adobe Type 1 fonts (PFB/PFA).

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `font_name` | String | Font name |
| `family_name` | String | Family name |
| `charstrings` | Hash | Glyph outlines |
| `private_dict` | Hash | Private dictionary |

## Methods

### glyph_count

Get total glyph count.

```ruby
count = font.glyph_count
```

### charstring(glyph_name)

Get CharString for a glyph.

```ruby
cs = font.charstring('A')
```

## See Also

- [FontLoader](/api/font-loader)
- [SfntFont](/api/sfnt-font)
