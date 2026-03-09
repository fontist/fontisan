---
title: PostScript Hinting
---

# PostScript Hinting

PostScript hints are declarative values stored in the CFF Private dictionary.

## Hint Parameters

### Blue Values

Alignment zones for vertical positioning:

| Parameter | Description | Max Values |
|-----------|-------------|------------|
| `blue_values` | Baseline and top zones | 14 (7 pairs) |
| `other_blues` | Descender zones | 10 (5 pairs) |

```ruby
# Example blue values
blue_values = [-20, 0, 700, 720]  # Baseline zone and cap height zone
other_blues = [-250, -230]        # Descender zone
```

### Stem Widths

Standard stem dimensions:

| Parameter | Description | Max Values |
|-----------|-------------|------------|
| `std_hw` | Standard horizontal stem | 1 |
| `std_vw` | Standard vertical stem | 1 |
| `stem_snap_h` | Horizontal stem snap values | 12 |
| `stem_snap_v` | Vertical stem snap values | 12 |

```ruby
# Example stem values
std_hw = 80    # Standard horizontal stem width
std_vw = 100   # Standard vertical stem width
stem_snap_h = [80, 90, 100]  # Common H stem widths
stem_snap_v = [100, 110, 120] # Common V stem widths
```

### Other Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `blue_scale` | Threshold for alignment zones | 0.039625 |
| `blue_shift` | Overshoot threshold | 7 |
| `blue_fuzz` | Blue zone expansion | 1 |
| `force_bold` | Force bold rendering | false |
| `language_group` | 0=Latin, 1=CJK | 0 |

## Reading Hints

```ruby
font = Fontisan::FontLoader.load('font.otf')
cff = font.tables['CFF']

# Get Private DICT
private = cff.top_dicts.first[:private]

# Read hint parameters
puts "Blue scale: #{private[:blue_scale]}"
puts "Std H width: #{private[:std_hw]}"
puts "Std V width: #{private[:std_vw]}"
puts "Blue values: #{private[:blue_values]}"
puts "Other blues: #{private[:other_blues]}"
puts "Stem snap H: #{private[:stem_snap_h]}"
puts "Stem snap V: #{private[:stem_snap_v]}"
```

## Validation

```ruby
validator = Fontisan::Hints::HintValidator.new

hints = {
  blue_scale: 0.039625,
  std_hw: 80,
  blue_values: [-20, 0, 700, 720]
}

result = validator.validate_postscript_hints(hints)

if result[:valid]
  puts "Valid PostScript hints"
else
  result[:errors].each { |err| puts "Error: #{err}" }
end
```

### Validation Checks

- **Value Ranges** — Validates hint parameter bounds
- **Pair Validation** — Ensures blue zones are in pairs (even count)
- **Array Limits** — Enforces CFF specification limits
- **Positive Values** — Verifies stem widths are positive
- **Language Group** — Validates value is 0 or 1

## Blue Zone Examples

### Latin Font

```ruby
blue_values = [
  -20, 0,      # Baseline zone (-20 to 0)
  470, 490,    # x-height zone (470 to 490)
  700, 720     # Cap height zone (700 to 720)
]

other_blues = [
  -250, -230   # Descender zone (-250 to -230)
]
```

### CJK Font

```ruby
blue_values = [
  -20, 0,      # Baseline
  880, 900     # Top zone
]

other_blues = []

language_group = 1  # CJK
```

## Stem Snap Values

Stem snaps tell the rasterizer which widths are "standard":

```ruby
# If stems in the font are primarily 80, 90, or 100 units
stem_snap_h = [80, 90, 100]

# The rasterizer will snap stems to these values
# when they're close enough
```

## Best Practices

1. **Keep blue zones in pairs** — Each zone needs top and bottom
2. **Use realistic values** — Stems should match actual glyph stems
3. **Don't over-specify** — 4-5 blue zones are usually enough
4. **Test at small sizes** — Verify hints improve rendering
5. **Consider font size** — Adjust blue_scale for text vs display
