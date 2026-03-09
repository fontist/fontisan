---
title: Format Conversion
---

# Format Conversion

Convert variable fonts between formats while preserving or converting variation data.

## Conversion Strategy

### Compatible Formats (Same Outline)

- Variable TTF ↔ Variable TTF/WOFF/WOFF2: All variation tables preserved
- Variable OTF ↔ Variable OTF/WOFF/WOFF2: All variation tables preserved

### Convertible Formats (Different Outline)

- Variable TTF ↔ Variable OTF: Common tables preserved (fvar, avar, STAT, metrics)
- Outline-specific tables require conversion (gvar ↔ CFF2 blend)

### Unsupported

- Variable fonts to SVG: Creates instance at default coordinates

## CLI Usage

### Preserve Variation

```bash
# Variable TTF to WOFF2 (preserves all variation)
fontisan convert variable.ttf --to woff2 --output variable.woff2

# Variable OTF to WOFF2 (preserves all variation)
fontisan convert variable.otf --to woff2 --output variable.woff2
```

### Convert Outline Format

```bash
# Variable TTF to OTF (preserves common variation tables)
fontisan convert variable.ttf --to otf --output variable.otf

# Note: Shows warning about gvar → CFF2 conversion
# Preserves: fvar, avar, STAT, HVAR, VVAR, MVAR
# Does not preserve: gvar (requires conversion to CFF2)
```

### Create Static Font

```bash
# Remove all variation data
fontisan convert variable.ttf --to ttf --output static.ttf --no-preserve-variation

# Creates static font at default variation coordinates
```

## Ruby API

### Preserve Variation

```ruby
font = Fontisan::FontLoader.load('variable.ttf')

# Convert with variation preservation
options = Fontisan::ConversionOptions.new(
  preserve_variation: true
)

Fontisan::FontWriter.write(font, 'variable.woff2', options: options)
```

### Convert Outline Format

```ruby
# Variable TTF to OTF
converter = Fontisan::Converters::OutlineConverter.new

options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  preserve_variation: true  # Preserves fvar, avar, STAT
)

result = converter.convert(font, options: options)
```

### Remove Variation

```ruby
# Create static font at default coordinates
writer = Fontisan::Variation::InstanceWriter.new(font)
static_font = writer.generate_instance({})  # Empty hash = default values

Fontisan::FontWriter.write(static_font, 'static.ttf')
```

## Tables Preserved

### Same Outline Format

All variation tables preserved:

| Table | Preserved |
|-------|-----------|
| fvar | ✓ |
| gvar | ✓ (TrueType) |
| CFF2 | ✓ (OpenType) |
| avar | ✓ |
| STAT | ✓ |
| HVAR | ✓ |
| VVAR | ✓ |
| MVAR | ✓ |

### Cross Outline Format

Common tables preserved:

| Table | Preserved |
|-------|-----------|
| fvar | ✓ |
| avar | ✓ |
| STAT | ✓ |
| HVAR | ✓ |
| VVAR | ✓ |
| MVAR | ✓ |
| gvar | ✗ (requires CFF2 conversion) |
| CFF2 | ✗ (requires gvar conversion) |

## Limitations

### gvar ↔ CFF2

Converting between TrueType (gvar) and OpenType (CFF2) variation data is not fully implemented:

- **TTF → OTF**: gvar variation data is lost
- **OTF → TTF**: CFF2 blend operators are lost

The fvar, avar, and STAT tables are preserved, but the actual glyph variation data is not.

### Workaround

Generate static instances before conversion:

```ruby
# Generate instances from variable TTF
writer = Fontisan::Variation::InstanceWriter.new(font)
instance = writer.generate_instance(wght: 700)

# Convert instance to OTF
converter = Fontisan::Converters::OutlineConverter.new
otf_font = converter.convert(instance, options: otf_options)
```

## Web Font Conversion

### Variable WOFF2

```bash
# Smallest file size with variation
fontisan convert variable.ttf --to woff2 --output variable.woff2
```

Benefits:
- 30-50% smaller than variable TTF
- All variation preserved
- Best for web delivery

### Instance Generation for Web

```bash
# Generate instances as WOFF2
fontisan instance variable.ttf --wght 700 --to woff2 --output bold.woff2
```

## Examples

### Convert Variable Font Family

```ruby
require 'fontisan'

# Load variable font
font = Fontisan::FontLoader.load('variable.ttf')

# Convert to WOFF2
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
Fontisan::FontWriter.write(font, 'variable.woff2', options: options)

# Generate key instances
fvar = font.tables['fvar']
writer = Fontisan::Variation::InstanceWriter.new(font)

[400, 500, 600, 700].each do |wght|
  instance = writer.generate_instance(wght: wght)
  Fontisan::FontWriter.write(instance, "weight-#{wght}.woff2", options: options)
end
```
