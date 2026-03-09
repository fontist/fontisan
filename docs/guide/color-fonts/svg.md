---
title: SVG Color Fonts
---

# SVG Color Fonts

SVG color fonts embed complete SVG documents for each glyph.

## Overview

SVG color fonts contain:
- Full SVG documents with shapes, gradients, effects
- Can be extremely detailed and complex
- Self-contained (no external resources)

## Structure

```ruby
svg = font.tables['SVG']

# SVG documents by glyph ID
svg.documents.each do |glyph_id, doc|
  puts "Glyph #{glyph_id}:"
  puts doc  # Complete SVG XML
end
```

## Reading SVG Fonts

### List SVG Glyphs

```ruby
font = Fontisan::FontLoader.load('svg-font.ttf')
svg = font.tables['SVG']

if svg
  svg.documents.each do |glyph_id, doc|
    glyph_name = font.glyph_name(glyph_id)
    puts "#{glyph_name}: #{doc.length} bytes"
  end
end
```

### Parse SVG Content

```ruby
require 'nokogiri'

svg = font.tables['SVG']
doc = svg.documents[42]  # SVG for glyph 42

parsed = Nokogiri::XML(doc)

# Find elements
paths = parsed.css('path')
puts "Paths: #{paths.length}"

rects = parsed.css('rect')
puts "Rectangles: #{rects.length}"

# Find gradients
gradients = parsed.css('linearGradient', 'radialGradient')
puts "Gradients: #{gradients.length}"
```

## SVG Features

SVG fonts can include:

| Feature | Support |
|---------|---------|
| Paths | ✓ |
| Basic shapes | ✓ |
| Gradients | ✓ |
| Patterns | ✓ |
| Clip paths | ✓ |
| Masks | ✓ |
| Filters | Limited |
| Animations | No |
| Scripts | No |

## Exporting

### Export SVG Files

```ruby
font = Fontisan::FontLoader.load('svg-font.ttf')
svg = font.tables['SVG']

Dir.mkdir('svg-glyphs') unless Dir.exist?('svg-glyphs')

svg.documents.each do |glyph_id, doc|
  glyph_name = font.glyph_name(glyph_id) || "glyph-#{glyph_id}"
  filename = "svg-glyphs/#{glyph_name}.svg"
  File.write(filename, doc)
end
```

## Conversion

### SVG to Other Formats

```bash
# SVG is preserved during conversion
fontisan convert svg-font.ttf --to otf --output svg-font.otf
```

### Remove SVG

```bash
# Create version without SVG
fontisan convert svg-font.ttf --to ttf --no-svg --output no-svg.ttf
```

## Limitations

### File Size

SVG fonts can be very large:
- XML text overhead
- Duplicate content across glyphs
- Embedded gradients and filters

### Browser Support

| Browser | Support |
|---------|---------|
| Firefox | Full |
| Safari | Full |
| Chrome | Full (since v98) |
| Edge | Full |

### Performance

- **Parsing** — SVG requires XML parsing
- **Rendering** — Complex effects are slow
- **Memory** — Large documents use more memory

## Comparison with COLR/CPAL

| Feature | SVG | COLR/CPAL |
|---------|-----|-----------|
| File size | Large | Small |
| Effects | Full | Limited |
| Gradients | Full | Limited |
| Browser support | Good | Good |
| Variable fonts | No | Yes |

## Best Practices

1. **Optimize SVGs** — Minimize file size
2. **Use COLR/CPAL if possible** — Better performance
3. **Test rendering** — Complex effects may not work everywhere
4. **Provide fallbacks** — Not all platforms support SVG fonts
