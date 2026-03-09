---
title: COLR/CPAL Color Fonts
---

# COLR/CPAL Color Fonts

COLR/CPAL is a modern color font format using layered vector glyphs.

## Overview

- **COLR** — Defines glyph layers and their order
- **CPAL** — Defines color palettes

## Structure

### COLR Table

```ruby
colr = font.tables['COLR']

# Base glyphs (color emoji)
base_glyphs = colr.base_glyphs

# Layers for a base glyph
layers = colr.layers_for(glyph_id)
# Returns array of { glyph_id:, palette_index: }
```

### CPAL Table

```ruby
cpal = font.tables['CPAL']

# Number of palettes
num_palettes = cpal.num_palettes

# Colors in a palette
palette_colors = cpal.palette(0)  # First palette

# Get specific color
color = cpal.color(palette_index)
# Returns { r:, g:, b:, a: }
```

## Working with COLR/CPAL

### List Color Glyphs

```ruby
font = Fontisan::FontLoader.load('color-font.ttf')
colr = font.tables['COLR']

colr.base_glyphs.each do |glyph_id|
  glyph_name = font.glyph_name(glyph_id)
  puts "#{glyph_name} (#{glyph_id})"
end
```

### Get Layer Colors

```ruby
colr = font.tables['COLR']
cpal = font.tables['CPAL']

colr.base_glyphs.each do |glyph_id|
  puts "Glyph #{glyph_id}:"

  colr.layers_for(glyph_id).each do |layer|
    color = cpal.color(layer[:palette_index])
    layer_name = font.glyph_name(layer[:glyph_id])
    puts "  #{layer_name}: rgba(#{color[:r]}, #{color[:g]}, #{color[:b]}, #{color[:a]})"
  end
end
```

## Color Palettes

### Default Palette

```ruby
cpal = font.tables['CPAL']

# First palette (default)
default_palette = cpal.palette(0)
puts "Default palette has #{default_palette.length} colors"
```

### Multiple Palettes

Some fonts have alternative color schemes:

```ruby
cpal = font.tables['CPAL']

(0...cpal.num_palettes).each do |palette_index|
  puts "Palette #{palette_index}:"
  cpal.palette(palette_index).each_with_index do |color, i|
    puts "  Color #{i}: rgba(#{color[:r]}, #{color[:g]}, #{color[:b]}, #{color[:a]})"
  end
end
```

## Conversion

### Preserve COLR/CPAL

```bash
# COLR/CPAL is preserved during same-format conversion
fontisan convert color-font.ttf --to otf --output color-font.otf
```

### Flatten to PNG

```bash
# Export color glyphs as PNG images
fontisan export color-font.ttf --format png --output ./images/
```

## Creating COLR/CPAL

Currently Fontisan focuses on reading and preserving COLR/CPAL. For creation, consider:

1. Design glyphs in layers
2. Assign palette indices
3. Define color palettes
4. Use font editor (Glyphs, FontForge)

## Browser Support

| Browser | Version |
|---------|---------|
| Chrome | 98+ |
| Firefox | 105+ |
| Safari | 15.4+ |
| Edge | 98+ |

## Validation

```bash
# Validate color font
fontisan validate color-font.ttf

# Check COLR structure
fontisan info color-font.ttf
```

## Example

### Analyze Color Emoji Font

```ruby
font = Fontisan::FontLoader.load('emoji.ttf')
colr = font.tables['COLR']
cpal = font.tables['CPAL']

puts "Color glyphs: #{colr.base_glyphs.length}"
puts "Palettes: #{cpal.num_palettes}"

# Find glyph for specific character
cmap = font.tables['cmap']
glyph_id = cmap.glyph_id_for('😀')

if colr.base_glyphs.include?(glyph_id)
  puts "😀 is a color glyph"

  layers = colr.layers_for(glyph_id)
  puts "Composed of #{layers.length} layers:"

  layers.each do |layer|
    layer_name = font.glyph_name(layer[:glyph_id])
    color = cpal.color(layer[:palette_index])
    puts "  #{layer_name}: rgba(#{color[:r]}, #{color[:g]}, #{color[:b]})"
  end
end
```
