---
title: Advanced Variable Font Topics
---

# Advanced Variable Font Topics

Advanced operations for variable fonts.

## avar Table

The avar (Axis Variation) table defines non-linear axis value mappings.

### What avar Does

Without avar, interpolation is linear:

```
wght 400 → wght 500 → wght 600 → wght 700
      50%        50%        50%
```

With avar, you can have non-linear interpolation:

```
wght 400 → wght 500 → wght 600 → wght 700
      70%        20%        10%
```

### Checking for avar

```ruby
font = Fontisan::FontLoader.load('variable.ttf')
avar = font.tables['avar']

if avar
  puts "Non-linear interpolation detected"

  avar.axis_mappings.each do |axis_tag, mapping|
    puts "#{axis_tag}:"
    mapping.each do |from, to|
      puts "  #{from} → #{to}"
    end
  end
end
```

## STAT Table

The STAT (Style Attributes) table provides style attributes and axis value names.

### STAT Benefits

- Better font menu organization
- Consistent naming across fonts
- Style linking information

### Reading STAT

```ruby
stat = font.tables['STAT']

if stat
  # Get design coordinates
  stat.design_axis_values.each do |axis_value|
    puts "#{axis_value.axis_tag}: #{axis_value.name}"
    puts "  Value: #{axis_value.value}"
  end
end
```

## Metrics Variation Tables

### HVAR (Horizontal Metrics Variation)

```ruby
hvar = font.tables['HVAR']

if hvar
  # Get advance width variation
  width_delta = hvar.advance_width_delta(glyph_id, coordinates)
  # Apply to base width
  final_width = base_width + width_delta
end
```

### MVAR (Metrics Variation)

```ruby
mvar = font.tables['MVAR']

if mvar
  # Get OS/2 typo ascender delta
  ascender_delta = mvar.metric_delta('hasc', coordinates)
end
```

### VVAR (Vertical Metrics Variation)

```ruby
vvar = font.tables['VVAR']

if vvar
  # Get vertical advance delta
  v_advance_delta = vvar.advance_height_delta(glyph_id, coordinates)
end
```

## Delta Processing

### Understanding Deltas

Variable fonts store changes (deltas) from the default:

```ruby
# Default glyph outline
default_outline = font.glyphs[glyph_id].outline

# Delta at wght=700
delta = gvar.delta_for_glyph(glyph_id, wght: 700)

# Apply delta to get bold outline
bold_outline = default_outline + delta
```

### Interpolation

```ruby
# Interpolate between two masters
weight = 600  # Between regular (400) and bold (700)

# Calculate interpolation factor
t = (weight - 400) / (700 - 400)  # 0.667

# Interpolate delta
interpolated_delta = gvar.interpolate(glyph_id, t, wght: weight)
```

## CFF2 Variable Fonts

### CFF2 vs CFF

| Feature | CFF | CFF2 |
|---------|-----|------|
| Variation | No | Yes |
| CharStrings | Standard | With blend operators |
| Private DICT | Per-font | Per-local |

### Reading CFF2

```ruby
cff2 = font.tables['CFF2']

if cff2
  # Get blend values for coordinates
  blend_values = cff2.blend_values(glyph_id, coordinates)

  # Access variation store
  variation_store = cff2.variation_store
end
```

## Validation

### Variable Font Validation

```ruby
# Validate variable font structure
result = Fontisan.validate('variable.ttf', profile: :production)

# Check variable-specific issues
if result.valid?
  # Verify fvar/gvar consistency
  fvar = font.tables['fvar']
  gvar = font.tables['gvar']

  if fvar && gvar
    # Check axis count matches
    unless gvar.axis_count == fvar.axes.length
      puts "Warning: gvar axis count mismatch"
    end
  end
end
```

### Common Issues

- **Missing gvar/CFF2**: Font has fvar but no variation data
- **Axis mismatch**: gvar axis count differs from fvar
- **Invalid coordinates**: Instance coordinates outside axis ranges
- **Missing default instance**: No default coordinates defined

## Performance Optimization

### Caching

```ruby
# Create writer once for multiple instances
writer = Fontisan::Variation::InstanceWriter.new(font)

# Cache is reused across calls
instances = weights.map { |w| writer.generate_instance(wght: w) }
```

### Batch Processing

```ruby
# Process multiple fonts in parallel
fonts = Dir.glob('fonts/*.ttf').map { |f| Fontisan::FontLoader.load(f) }

fonts.map do |font|
  Thread.new do
    writer = Fontisan::Variation::InstanceWriter.new(font)
    writer.generate_instance(wght: 700)
  end
end.each(&:join)
```

## SVG Generation

### Limitations

Variable fonts cannot be directly exported to SVG. Generate static instances first:

```ruby
# Generate instance
writer = Fontisan::Variation::InstanceWriter.new(font)
static = writer.generate_instance(wght: 700)

# Export to SVG
Fontisan::FontWriter.write(static, 'bold.svg', format: :svg)
```
