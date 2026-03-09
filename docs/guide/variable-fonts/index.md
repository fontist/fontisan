---
title: Variable Fonts Overview
---

# Variable Fonts Overview

Variable fonts are OpenType fonts that contain multiple variations of a typeface in a single file. Instead of having separate font files for different weights, widths, or styles, a variable font uses variation axes to interpolate between different design extremes.

## Key Tables

| Table | Description |
|-------|-------------|
| `fvar` | Defines variation axes and named instances |
| `gvar` | (TrueType) Glyph variation data as delta tuples |
| `CFF2` | (OpenType) Variation data as blend operators |
| `avar` | (Optional) Axis value mappings for non-linear interpolation |
| `STAT` | (Optional) Style attributes and axis value names |
| `HVAR/VVAR/MVAR` | (Optional) Metrics variation tables |

## Variation Axes

Each axis represents a design dimension along which the font can vary.

### Common Registered Axes

| Tag | Name | Range | Typical Values |
|-----|------|-------|----------------|
| `wght` | Weight | 1-1000 | 400 (Regular) to 700 (Bold) |
| `wdth` | Width | 1-1000 | 75 (Condensed) to 125 (Expanded) |
| `slnt` | Slant | -90 to 90 | Degrees |
| `ital` | Italic | 0 or 1 | 0 (Roman), 1 (Italic) |
| `opsz` | Optical Size | Varies | Point size for optical sizing |

### Custom Axes

Custom axes use four-character tags starting with uppercase letter:

- `GRAD` — Grade
- `XOPQ` — X-Optical-Size
- `YOPQ` — Y-Optical-Size
- `XTRA` — X-Transparency
- And many others...

## Named Instances

Variable fonts can define named instances — predefined points in the design space with specific names:

- "Regular"
- "Bold"
- "Light"
- "Condensed Bold"
- "Expanded Italic"

## Guides

- [Axes & Instances](/guide/variable-fonts/axes) — Working with axes and named instances
- [Instance Generation](/guide/variable-fonts/instances) — Generate static fonts from variable fonts
- [Format Conversion](/guide/variable-fonts/conversion) — Convert variable fonts between formats
- [Named Instances](/guide/variable-fonts/named-instances) — Work with named instances
- [Static Fonts](/guide/variable-fonts/static) — Convert to static fonts
- [Advanced Topics](/guide/variable-fonts/advanced) — Advanced variable font operations

## Quick Start

### Get Axis Information

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
fvar = font.tables['fvar']

fvar.axes.each do |axis|
  puts "#{axis.tag}: #{axis.min_value} - #{axis.max_value}"
end
```

### Generate Instance

```bash
# Generate bold instance
fontisan instance variable.ttf --wght 700 --output bold.ttf

# Generate with multiple axes
fontisan instance variable.ttf --wght 700 --wdth 75 --output condensed-bold.ttf
```
