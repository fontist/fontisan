---
title: Curve Conversion
---

# Curve Conversion

Fontisan handles conversion between TrueType's quadratic Bézier curves and OpenType/CFF's cubic Bézier curves.

## Overview

| Format | Curve Type | Math |
|--------|------------|------|
| TrueType (TTF) | Quadratic Bézier | 1 control point |
| OpenType/CFF (OTF) | Cubic Bézier | 2 control points |

## Quadratic Bézier Curves (TrueType)

Quadratic curves have one control point between two on-curve points:

```
P0 ---- Q1 ---- P2

Where:
- P0, P2 are on-curve points
- Q1 is the control point
```

### Formula

```
B(t) = (1-t)²·P0 + 2(1-t)t·Q1 + t²·P2
```

## Cubic Bézier Curves (OpenType/CFF)

Cubic curves have two control points:

```
P0 -- C1 -- C2 -- P3

Where:
- P0, P3 are on-curve points
- C1, C2 are control points
```

### Formula

```
B(t) = (1-t)³·P0 + 3(1-t)²t·C1 + 3(1-t)t²·C2 + t³·P3
```

## Quadratic → Cubic (TTF → OTF)

This conversion is mathematically exact.

### Conversion Process

```ruby
# TrueType quadratic: P0, Q1, P2
# Converts to cubic: P0, C1, C2, P2
#
# C1 = P0 + (2/3)(Q1 - P0)
# C2 = P2 + (2/3)(Q1 - P2)
```

### Example

```ruby
# Source: TrueType quadratic curve
p0 = [100, 100]
q1 = [150, 200]  # control point
p2 = [200, 100]

# Convert to cubic
c1 = [
  p0[0] + (2.0/3) * (q1[0] - p0[0]),  # 133.33
  p0[1] + (2.0/3) * (q1[1] - p0[1])   # 166.67
]
c2 = [
  p2[0] + (2.0/3) * (q1[0] - p2[0]),  # 166.67
  p2[1] + (2.0/3) * (q1[1] - p2[1])   # 166.67
]

# Result: [100, 100] -> [133.33, 166.67] -> [166.67, 166.67] -> [200, 100]
```

### Characteristics

- **Exact** — No approximation needed
- **Point count may increase** — Due to implicit on-curve points in TrueType

## Cubic → Quadratic (OTF → TTF)

This conversion requires approximation since cubic curves cannot be exactly represented as quadratic.

### Approximation Methods

Fontisan uses the midpoint approximation method:

```ruby
# Cubic: P0, C1, C2, P3
# Approximate with multiple quadratic curves
#
# Method: Subdivide until quadratic fits within tolerance
```

### Tolerance Setting

```ruby
options = Fontisan::ConversionOptions.new(
  curve_tolerance: 0.5  # Lower = more accurate, more points
)
```

| Tolerance | Accuracy | Point Count |
|-----------|----------|-------------|
| 1.0 | Lower | Fewer |
| 0.5 | Medium | Medium |
| 0.1 | Higher | More |

### Example

```ruby
# Source: Cubic curve
p0 = [100, 100]
c1 = [120, 200]
c2 = [180, 200]
p3 = [200, 100]

# May require 2+ quadratic curves:
# Quad 1: P0 -> Q1 -> P_mid
# Quad 2: P_mid -> Q2 -> P3
```

### Characteristics

- **Approximate** — Some precision loss unavoidable
- **Point count increases** — Multiple quadratic curves per cubic
- **Tolerance affects quality** — Lower tolerance = more accurate

## Implicit On-Curve Points

TrueType uses an optimization where on-curve points can be implicit:

```ruby
# If two consecutive off-curve points exist,
# the midpoint is an implicit on-curve point
#
# Q1 ---- (implicit P) ---- Q2
#
# P = (Q1 + Q2) / 2
```

This can reduce point count but must be expanded for conversion.

## Curve Conversion Options

### CLI

```bash
# Enable curve conversion
fontisan convert font.ttf --to otf --convert-curves

# With tolerance (OTF → TTF only)
fontisan convert font.otf --to ttf --curve-tolerance 0.5
```

### API

```ruby
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: {
    convert_curves: true
  },
  curve_tolerance: 0.5  # For OTF → TTF
)
```

## Preserving Curves

To skip curve conversion (same-format operations):

```ruby
options = Fontisan::ConversionOptions.new(
  opening: { convert_curves: false }
)
```

## Quality vs Size Trade-off

### TTF → OTF

- **No trade-off** — Exact conversion
- File size may increase due to explicit points

### OTF → TTF

- **Trade-off exists** — Approximation required
- Lower tolerance = better quality, larger files
- Higher tolerance = lower quality, smaller files

```bash
# High quality
fontisan convert font.otf --to ttf --curve-tolerance 0.1

# Smaller file
fontisan convert font.otf --to ttf --curve-tolerance 1.0
```

## Technical Details

### Checking Curve Types

```ruby
font = Fontisan::FontLoader.load('font.ttf')

# Check glyph format
glyph = font.glyphs[0]
puts glyph.curve_type  # :quadratic or :cubic
```

### Counting Points

```ruby
font = Fontisan::FontLoader.load('font.ttf')

total_on_curve = 0
total_off_curve = 0

font.glyphs.each do |glyph|
  glyph.contours.each do |contour|
    contour.points.each do |point|
      if point.on_curve?
        total_on_curve += 1
      else
        total_off_curve += 1
      end
    end
  end
end

puts "On-curve: #{total_on_curve}"
puts "Off-curve: #{total_off_curve}"
```
