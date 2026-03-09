---
title: Hint Conversion
---

# Hint Conversion

Fontisan provides bidirectional hint conversion between TrueType and PostScript formats.

## Overview

| Direction | From | To | Process |
|-----------|------|-----|---------|
| TTF → OTF | TrueType instructions | PostScript hints | Analyze bytecode |
| OTF → TTF | PostScript hints | TrueType instructions | Generate bytecode |

## TTF → OTF Conversion

### Process

```
TrueType Font → Instruction Analysis → PostScript Parameters → CFF Table
   (Input)       (prep/fpgm/cvt)      (Hint Dict)        (Output)
```

### Analysis Steps

1. Parse prep (Control Value Program) bytecode
2. Analyze fpgm (Font Program) for complexity indicators
3. Extract blue zones from CVT (Control Value Table) values
4. Extract stem widths and alignment zones

### Generated Parameters

| Parameter | Source |
|-----------|--------|
| `blue_scale` | CVT analysis |
| `std_hw` | CVT[0] (standard horizontal stem) |
| `std_vw` | CVT[1] (standard vertical stem) |
| `stem_snap_h` | CVT analysis |
| `stem_snap_v` | CVT analysis |
| `blue_values` | CVT analysis (baseline, cap) |
| `other_blues` | CVT analysis (descender) |

### CLI

```bash
fontisan convert font.ttf --to otf --hinting-mode preserve
```

### API

```ruby
converter = Fontisan::Converters::HintConverter.new

# Convert TrueType hints to PostScript
ps_hints = converter.truetype_to_postscript(font)

# Result contains:
# {
#   blue_scale: 0.039625,
#   std_hw: 80,
#   std_vw: 100,
#   blue_values: [-20, 0, 700, 720],
#   stem_snap_h: [80, 90],
#   stem_snap_v: [100, 110]
# }
```

## OTF → TTF Conversion

### Process

```
OTF Font → Parameter Extraction → Instruction Generation → TrueType Tables
 (Input)    (CFF Private Dict)    (prep/fpgm/cvt)        (Output)
```

### Generation Steps

1. Generate prep program with CVT cut-in, single width settings
2. Build CVT table with stem widths and blue zone values
3. Create fpgm program (typically empty for converted fonts)
4. Encode instructions using optimal PUSH opcodes

### Generated Tables

| Table | Content |
|-------|---------|
| `prep` | Control Value Program with hint setup |
| `cvt` | Control Value Table with stems and blue zones |
| `fpgm` | Font Program (empty for converted fonts) |

### CLI

```bash
fontisan convert font.otf --to ttf --hinting-mode preserve
```

### API

```ruby
converter = Fontisan::Converters::HintConverter.new

# Convert PostScript hints to TrueType
ttf_tables = converter.postscript_to_truetype(font)

# Result contains:
# {
#   prep: "\xB0\x11\x1D",  # Bytecode
#   cvt: [80, 100, -20, 0, 700, 720],
#   fpgm: ""
# }
```

## Round-Trip Conversion

Fontisan ensures hint integrity through round-trip conversion:

```
Original PS Hints → TrueType → PostScript → Validation
     (Input)         (Convert)   (Convert)    (Verify)
```

### Round-Trip Guarantees

- CVT values preserved (sorted and deduplicated)
- Standard widths (std_hw, std_vw) maintained
- Blue zone values retained
- <10% loss tolerance for approximations

### Known Limitations

- CVT sorting may change positions (optimization trade-off)
- blue_scale not perfectly round-trippable (conversion approximation)
- Standard widths extracted from CVT[0] and CVT[1] positions

## Example

```ruby
# Round-trip test
font = Fontisan::FontLoader.load('font.otf')
original_hints = font.tables['CFF'].top_dicts.first[:private]

# Convert to TrueType
ttf_converter = Fontisan::Converters::HintConverter.new
ttf_tables = ttf_converter.postscript_to_truetype(font)

# Convert back to PostScript
ps_hints = ttf_converter.truetype_to_postscript(ttf_font)

# Compare
puts "Original std_hw: #{original_hints[:std_hw]}"
puts "Round-trip std_hw: #{ps_hints[:std_hw]}"
```

## Best Practices

1. **Test round-trip** — Verify hint preservation
2. **Use autohint for cross-format** — Consider `--hinting-mode auto`
3. **Validate after conversion** — Check hint validity
4. **Test rendering** — Verify visual quality at small sizes
