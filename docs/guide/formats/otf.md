---
title: OpenType (OTF)
---

# OpenType (OTF)

OpenType/CFF uses cubic Bézier curves in a Compact Font Format.

## Overview

- **Curve Type**: Cubic Bézier
- **Hinting**: PostScript hints
- **Storage**: CFF table

## Key Tables

| Table | Purpose |
|-------|---------|
| head | Font header |
| hhea | Horizontal header |
| maxp | Maximum profile |
| name | Name records |
| cmap | Character mapping |
| CFF | Compact Font Format |
| hmtx | Horizontal metrics |
| post | PostScript names |
| OS/2 | OS/2 metrics |
| GSUB | Glyph substitution |
| GPOS | Glyph positioning |

## CFF Table Structure

```ruby
cff = font.tables['CFF']

# Top DICT
top_dict = cff.top_dicts.first

# Name
puts "Font name: #{cff.names.first}"

# Private DICT
private = top_dict[:private]
puts "Blue values: #{private[:blue_values]}"
puts "Std HW: #{private[:std_hw]}"
```

## CharStrings

```ruby
cff = font.tables['CFF']

# Access CharStrings
charstrings = cff.charstrings

charstrings.each_with_index do |charstring, glyph_id|
  puts "Glyph #{glyph_id}: #{charstring.length} operators"
end
```

## Hinting

OpenType fonts use PostScript hints:

```ruby
private = font.tables['CFF'].top_dicts.first[:private]

# Blue zones
puts "Blue values: #{private[:blue_values]}"
puts "Other blues: #{private[:other_blues]}"

# Stem widths
puts "Std HW: #{private[:std_hw]}"
puts "Std VW: #{private[:std_vw]}"
puts "Stem snap H: #{private[:stem_snap_h]}"
```

## Converting

### OTF to TTF

```bash
fontisan convert font.otf --to ttf --output font.ttf
```

### OTF to WOFF2

```bash
fontisan convert font.otf --to woff2 --output font.woff2
```

## Characteristics

### Advantages

- **Smaller file size** — CFF compression
- **Cubic curves** — Fewer points needed
- **PostScript heritage** — Print workflows

### Limitations

- **Limited hinting** — PostScript hints vs TrueType
- **Variable support** — CFF2 required
