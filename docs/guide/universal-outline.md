---
title: Universal Outline Model
---

# Universal Outline Model

The Fontisan Universal Outline Model (UOM) provides a format-agnostic representation of glyph contours that enables seamless conversion between different font formats.

## Overview

The UOM is based on a self-stable algorithm for converting soft glyph contours to outline format. This architecture allows:

- Importing glyphs from any font format (TrueType, OpenType, CFF)
- Converting glyph elements between formats
- Operating on outlines with transformations
- Serialization and storage

## Core Components

### Locker

The Locker is an object-oriented model for storing imported outlines and glyphs. Storage is based on monotonic spirals computed from 2D points and curves.

**Features:**
- Invisible conversion from TrueType, CFF OpenType, and ColorGlyph formats
- Preserves original glyph geometry
- Supports compound glyph decomposition

### Translator

The Translator is an object-oriented model for converting between PostScript CFF charsets.

**Features:**
- PostScript Type 2/3/composite encoding and decoding
- CFF INDEX structure building
- CFF DICT structure building
- Charset conversion

### ColorGlyph

ColorGlyph provides support for layered CFF color glyphs with on-demand rasterization.

**Features:**
- Composite font support
- Multi-layer color font representation
- CFF fonts stacked on top of each other
- Advanced color glyphs
- Raster image support (PNG/JPG) combined with TrueType outlines

## Universal Fonts

Fontisan provides universal font capabilities:

| Capability | Description |
|------------|-------------|
| Import | Import TrueType contours into UOM |
| Operate | Transform, clean, improve, and render outlines |
| Convert | Convert UOM contours to TTF/OTF |
| Serialize | Save and share font structures |
| Color Support | Work with advanced color fonts |

## Universal Glyphs

The universal glyph model enables:

- Universal Outline Model (UOM) for TrueType contours and CFF color glyphs
- Repository for custom fonts
- Custom Unicode assignments and configuration
- Outline import/export (TrueType and OTF/CFF)
- Rendering for advanced font types
- Universal layer stacking for color glyph combinations

## Universal Color Layers

Universal color layers support advanced color font operations:

| Feature | Description |
|---------|-------------|
| Import | Import embedded TTF/OTF color layers |
| Assemble | Assemble from individual TTF/OTF slices |
| Manage | Advanced layer map management in TTF color fonts |
| Blend | Advanced color layer blending style management |
| Convert | Gray/Overprint/Color-Full image comps and layer conversion |
| Raster | Smart vector combos from raster images |
| PNG | Import and generate PNG block ruler layers |

## Curve Conversion

The UOM handles bidirectional curve conversion:

- **TrueType → CFF**: Quadratic to cubic curve conversion
- **CFF → TrueType**: Cubic to quadratic curve conversion
- **CFF2 Support**: Variable font CFF2 outlines

## Ruby API

### Loading Outlines

```ruby
require 'fontisan'

# Load font and access universal outlines
font = Fontisan::FontLoader.load('font.ttf')

# Access glyphs through universal model
glyphs = font.glyphs

glyphs.each do |glyph|
  # Access universal outline representation
  outline = glyph.universal_outline

  # Get contour count
  puts "Glyph #{glyph.name}: #{outline.contour_count} contours"

  # Access points and curves
  outline.contours.each do |contour|
    contour.commands.each do |cmd|
      case cmd.type
      when :move_to
        puts "  Move to #{cmd.x}, #{cmd.y}"
      when :line_to
        puts "  Line to #{cmd.x}, #{cmd.y}"
      when :quad_to
        puts "  Quadratic curve to #{cmd.x}, #{cmd.y}"
      when :curve_to
        puts "  Cubic curve to #{cmd.x}, #{cmd.y}"
      end
    end
  end
end
```

### Converting Outlines

```ruby
# Convert between curve types
converter = Fontisan::Converters::CurveConverter.new

# TrueType (quadratic) to CFF (cubic)
cff_outlines = converter.quad_to_cubic(truetype_outlines)

# CFF (cubic) to TrueType (quadratic)
ttf_outlines = converter.cubic_to_quad(cff_outlines)
```

## Related Documentation

- [Curve Converter API](/api/converters/curve-converter) — Curve conversion details
- [Outline Converter API](/api/converters/outline-converter) — Full outline conversion
- [Font Conversion Guide](/guide/conversion/) — Conversion workflows
- [Color Fonts Guide](/guide/color-fonts/) — Color font support
