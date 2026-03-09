---
title: Static Fonts
---

# Static Fonts

Convert variable fonts to static fonts.

## Overview

Static fonts are traditional fonts with fixed designs. Converting a variable font to static creates a snapshot at specific coordinates.

## When to Use Static Fonts

- **Legacy Compatibility** — Older systems that don't support variable fonts
- **Performance** — Smaller file size for single weights
- **Simplicity** — No need for variation handling
- **Distribution** — Some platforms don't support variable fonts

## Creating Static Fonts

### At Default Coordinates

```bash
# Create static font at default variation
fontisan convert variable.ttf --to ttf --output static.ttf
```

### At Specific Coordinates

```bash
# Create static bold font
fontisan instance variable.ttf --wght 700 --output bold-static.ttf
```

### Remove Variation Data

```bash
# Explicitly remove variation tables
fontisan convert variable.ttf --to ttf --no-preserve-variation --output static.ttf
```

## API Usage

### Default Coordinates

```ruby
font = Fontisan::FontLoader.load('variable.ttf')

# Generate at default (empty hash = all default values)
writer = Fontisan::Variation::InstanceWriter.new(font)
static_font = writer.generate_instance({})

Fontisan::FontWriter.write(static_font, 'static.ttf')
```

### Specific Coordinates

```ruby
# Generate static at specific coordinates
static_bold = writer.generate_instance(wght: 700)
Fontisan::FontWriter.write(static_bold, 'bold-static.ttf')

# Generate static with multiple axes
static_condensed_bold = writer.generate_instance(wght: 700, wdth: 75)
Fontisan::FontWriter.write(static_condensed_bold, 'condensed-bold.ttf')
```

## What Gets Removed

When creating a static font, these tables are removed:

| Table | Status |
|-------|--------|
| fvar | Removed |
| gvar | Removed |
| CFF2 | Converted to CFF |
| avar | Removed |
| HVAR | Applied to hmtx, removed |
| VVAR | Applied to vmtx, removed |
| MVAR | Applied to tables, removed |

## What Gets Generated

The static font contains:

| Table | Source |
|-------|--------|
| glyf | Interpolated from gvar |
| CFF | Interpolated from CFF2 |
| hmtx | Interpolated from HVAR |
| vmtx | Interpolated from VVAR |
| Other tables | Copied unchanged |

## Batch Generation

### Generate Weight Range

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
writer = Fontisan::Variation::InstanceWriter.new(font)

weights = {
  'thin' => 100,
  'light' => 300,
  'regular' => 400,
  'medium' => 500,
  'semibold' => 600,
  'bold' => 700,
  'extrabold' => 800,
  'black' => 900
}

weights.each do |name, wght|
  static_font = writer.generate_instance(wght: wght)

  # Also convert to WOFF2 for web
  options = Fontisan::ConversionOptions.from_preset(:web_optimized)
  Fontisan::FontWriter.write(static_font, "#{name}.woff2", options: options)
end
```

### Generate 2D Grid

```ruby
# Generate grid of weight × width combinations
weights = [100, 400, 700]
widths = [75, 100, 125]

weights.each do |wght|
  widths.each do |wdth|
    static_font = writer.generate_instance(wght: wght, wdth: wdth)
    filename = "wght-#{wght}-wdth-#{wdth}.ttf"
    Fontisan::FontWriter.write(static_font, filename)
  end
end
```

## File Size Comparison

| Font Type | Typical Size |
|-----------|--------------|
| Variable font | 100-300 KB |
| Static (single) | 20-50 KB |
| Static (9 weights) | 180-450 KB |

Variable fonts are smaller when you need multiple variations. Static fonts are smaller for single variations.

## Quality Considerations

### Interpolation Accuracy

Static fonts are mathematically precise interpolations:

```ruby
# The interpolated outlines match the variable font exactly
# at the specified coordinates
```

### Hinting

- TrueType hints are interpolated along with outlines
- Some hint instructions may not apply to new coordinates
- Consider re-hinting after generation

### Subpixel Rendering

Static fonts may render differently than variable fonts at the same coordinates due to hinting differences.
