---
title: TrueType (TTF)
---

# TrueType (TTF)

TrueType is a standard font format using quadratic Bézier curves.

## Overview

- **Curve Type**: Quadratic Bézier
- **Hinting**: TrueType instructions
- **Storage**: glyf + loca tables

## Key Tables

| Table | Purpose |
|-------|---------|
| head | Font header |
| hhea | Horizontal header |
| maxp | Maximum profile |
| name | Name records |
| cmap | Character mapping |
| glyf | Glyph outlines |
| loca | Glyph locations |
| hmtx | Horizontal metrics |
| post | PostScript names |
| prep | Control Value Program |
| fpgm | Font Program |
| cvt | Control Value Table |

## Loading

```ruby
font = Fontisan::FontLoader.load('font.ttf')

# Access tables
head = font.tables['head']
glyf = font.tables['glyf']

puts "Units per Em: #{head.units_per_em}"
puts "Glyphs: #{font.tables['maxp'].num_glyphs}"
```

## Glyph Outlines

```ruby
glyph = font.glyphs[42]

# Access outline
glyph.contours.each do |contour|
  contour.points.each do |point|
    if point.on_curve?
      puts "Point at (#{point.x}, #{point.y})"
    else
      puts "Control at (#{point.x}, #{point.y})"
    end
  end
end
```

## Hinting

TrueType fonts use bytecode instructions:

```ruby
prep = font.tables['prep']
fpgm = font.tables['fpgm']
cvt = font.tables['cvt']

if prep
  puts "Prep program: #{prep.bytecode.length} bytes"
end

if cvt
  puts "CVT entries: #{cvt.values.length}"
end
```

## Converting

### TTF to OTF

```bash
fontisan convert font.ttf --to otf --output font.otf
```

### TTF to WOFF2

```bash
fontisan convert font.ttf --to woff2 --output font.woff2
```

## Characteristics

### Advantages

- **Wide support** — All platforms
- **Excellent hinting** — TrueType instructions
- **Variable fonts** — gvar support

### Limitations

- **Larger file size** — Compared to CFF
- **Quadratic curves** — More points for complex shapes
