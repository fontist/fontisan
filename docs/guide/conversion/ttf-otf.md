---
title: TTF ↔ OTF Conversion
---

# TTF ↔ OTF Conversion

Converting between TrueType (TTF) and OpenType/CFF (OTF) formats involves curve conversion and hinting system changes.

## Overview

| Source | Target | Curve Type | Hinting System |
|--------|--------|------------|----------------|
| TTF | OTF | Quadratic → Cubic | TrueType → CFF |
| OTF | TTF | Cubic → Quadratic | CFF → TrueType |

## TTF → OTF

Convert TrueType fonts to OpenType/CFF format.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)
# Returns:
# opening: { convert_curves: true, scale_to_1000: true, autohint: true,
#           decompose_composites: false, store_custom_tables: true }
# generating: { hinting_mode: "auto", decompose_on_output: true }
```

### CLI

```bash
# Basic conversion
fontisan convert font.ttf --to otf --output font.otf

# With autohint
fontisan convert font.ttf --to otf --autohint --output font.otf

# Show options that will be used
fontisan convert font.ttf --to otf --show-options
```

### Key Considerations

- **Curve conversion**: Quadratic → Cubic (mathematically exact, but may increase point count)
- **Hinting**: TrueType instructions → CFF hints (lossy conversion)
- **Scaling**: Typically 2048 UPM → 1000 UPM

### Limitations

- TrueType hinting instructions are NOT converted to CFF hints
- GSUB/GPOS features preserved but table format changes

## OTF → TTF

Convert OpenType/CFF fonts to TrueType format.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :otf, to: :ttf)
# Returns:
# opening: { decompose_composites: false, read_all_records: true,
#           interpret_ot: true, store_custom_tables: true,
#           store_native_hinting: false }
# generating: { hinting_mode: "full", reencode_first_256: false }
```

### CLI

```bash
# Basic conversion
fontisan convert font.otf --to ttf --output font.ttf

# With full hinting
fontisan convert font.otf --to ttf --hinting-mode full --output font.ttf
```

### Key Considerations

- **Curve conversion**: Cubic → Quadratic (requires approximation)
- **Hinting**: CFF hints → TrueType instructions (lossy conversion)
- **OpenType features**: Interpreted before conversion

### Limitations

- CFF cubic curves must be approximated as TrueType quadratic curves
- Multiple quadratic curves may be needed for accuracy
- Some precision loss in curve approximation is unavoidable

## Same-Format Copy

### TTF → TTF

```ruby
Fontisan::ConversionOptions.recommended(from: :ttf, to: :ttf)
# opening: { convert_curves: false, scale_to_1000: false,
#            decompose_composites: false, autohint: false,
#            store_custom_tables: true, store_native_hinting: true }
# generating: { hinting_mode: "preserve", write_custom_tables: true,
#              optimize_tables: true }
```

Use cases: Copy with optimization, metadata updates

### OTF → OTF

```ruby
Fontisan::ConversionOptions.recommended(from: :otf, to: :otf)
# opening: { decompose_composites: false, store_custom_tables: true,
#            interpret_ot: true }
# generating: { hinting_mode: "preserve", decompose_on_output: false,
#              write_custom_tables: true, optimize_tables: true }
```

Use cases: Copy with optimization, metadata updates

## Curve Conversion Details

### Quadratic → Cubic (TTF → OTF)

This conversion is mathematically exact:

```ruby
# TrueType quadratic Bézier
# P0, P1, P2 where P1 is the control point

# Converts to cubic Bézier
# P0, C1, C2, P2 where:
# C1 = P0 + (2/3)(P1 - P0)
# C2 = P2 + (2/3)(P1 - P2)
```

Result: Exact representation, but may increase point count.

### Cubic → Quadratic (OTF → TTF)

This conversion requires approximation:

```ruby
# Cubic Bézier cannot be exactly represented as quadratic
# Requires splitting into multiple quadratic curves

# Approximation tolerance controls accuracy
options = Fontisan::ConversionOptions.new(
  curve_tolerance: 0.5  # Lower = more accurate, more points
)
```

Result: Some precision loss unavoidable.

## Examples

### Batch Conversion

```ruby
# Convert all TTF files in a directory
Dir.glob('fonts/*.ttf').each do |input|
  output = input.sub('.ttf', '.otf')
  Fontisan.convert(input, output_format: :otf, output_path: output)
end
```

### With Custom Options

```ruby
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: {
    convert_curves: true,
    scale_to_1000: true,
    autohint: true
  },
  generating: {
    hinting_mode: 'auto',
    optimize_tables: true
  }
)

converter = Fontisan::Converters::OutlineConverter.new
result = converter.convert(font, options: options)
Fontisan::FontWriter.write(result, 'output.otf')
```
