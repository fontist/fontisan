---
title: Color Fonts Overview
---

# Color Fonts Overview

Fontisan supports multiple color font formats for modern typography.

## Supported Formats

| Format | Tables | Description |
|--------|--------|-------------|
| COLR/CPAL | COLR, CPAL | Layered vector glyphs |
| sbix | sbix | Bitmap images (Apple) |
| CBDT/CBLC | CBDT, CBLC | Bitmap images (Google) |
| SVG | SVG | SVG embedded in font |

## COLR/CPAL

COLR/CPAL uses layered vector glyphs with palette-based coloring.

### Advantages

- **Scalable** — Vectors scale to any size
- **Small file size** — Efficient compression
- **Variable support** — Works with variable fonts
- **Wide support** — Modern browsers and apps

### Structure

```
COLR table:
- Glyph layers (which glyphs make up each color glyph)
- Layer order (back to front)

CPAL table:
- Color palettes (sets of colors)
- Color values (RGBA for each palette entry)
```

## sbix

sbix stores bitmap images at multiple resolutions (Apple format).

### Advantages

- **Photo-realistic** — Any image quality
- **Multiple sizes** — Different bitmaps for different sizes

### Structure

```
sbix table:
- Strikes (image sets at different sizes)
- Per-glyph images (PNG, JPG, etc.)
```

## CBDT/CBLC

CBDT/CBLC stores bitmap images (Google/Android format).

### Advantages

- **Android support** — Primary Android bitmap format
- **Multiple sizes** — Different bitmaps per ppem

### Structure

```
CBLC table:
- Location data (where each bitmap is)
- Size information

CBDT table:
- Bitmap data (actual images)
```

## SVG Color Fonts

SVG fonts embed complete SVG documents.

### Advantages

- **Full SVG features** — Gradients, effects, etc.
- **Standalone** — No external resources

### Limitations

- **Large file size** — XML overhead
- **Limited support** — Not all browsers

## Guides

- [COLR/CPAL](/guide/color-fonts/colr-cpal) — Vector layered color fonts
- [Bitmaps](/guide/color-fonts/bitmaps) — sbix and CBDT/CBLC
- [SVG Color](/guide/color-fonts/svg) — SVG-based color fonts

## Quick Start

### Check for Color Tables

```ruby
font = Fontisan::FontLoader.load('font.ttf')

if font.tables['COLR']
  puts "COLR/CPAL color font"
end

if font.tables['sbix']
  puts "sbix bitmap font"
end

if font.tables['CBDT']
  puts "CBDT/CBLC bitmap font"
end

if font.tables['SVG']
  puts "SVG color font"
end
```

### Get Color Information

```ruby
colr = font.tables['COLR']
cpal = font.tables['CPAL']

if colr && cpal
  # Get base glyphs (color emoji)
  colr.base_glyphs.each do |glyph_id|
    puts "Base glyph: #{glyph_id}"
    puts "  Layers: #{colr.layers_for(glyph_id).length}"

    colr.layers_for(glyph_id).each do |layer|
      color = cpal.color(layer[:palette_index])
      puts "    Layer #{layer[:glyph_id]}: #{color}"
    end
  end
end
```
