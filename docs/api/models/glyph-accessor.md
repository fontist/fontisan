---
title: GlyphAccessor
---

# GlyphAccessor

Unified glyph access with caching.

## Overview

`Fontisan::GlyphAccessor` provides efficient glyph access.

## Methods

### at(id) / get(id)

Access glyph by ID.

```ruby
glyph = font.glyphs[42]
```

### each

Iterate over all glyphs.

```ruby
font.glyphs.each do |glyph|
  puts glyph.name
end
```

### count

Get glyph count.

```ruby
count = font.glyphs.count
```

## See Also

- [Glyph](/api/models/glyph)
