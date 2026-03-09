---
title: Type 1 (PFB/PFA)
---

# Type 1 (PFB/PFA)

Adobe Type 1 fonts are legacy PostScript fonts.

## Overview

- **Curve Type**: Cubic Bézier
- **Hinting**: PostScript hints
- **Formats**: PFB (binary), PFA (ASCII)

## File Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| PFB | .pfb | Binary format |
| PFA | .pfa | ASCII format |

## Structure

Type 1 fonts contain:

1. **Font Dictionary** — Font info, encoding
2. **Private Dictionary** — Hinting parameters
3. **CharStrings** — Glyph outlines
4. **Subroutines** — Reusable outline segments

## Encryption

Type 1 fonts use encryption:

| Section | Key |
|---------|-----|
| eexec | 55665 |
| CharStrings | 4330 |

Fontisan handles decryption automatically.

## Loading

```ruby
font = Fontisan::FontLoader.load('font.pfb')

# Access font info
puts "Family: #{font.family_name}"
puts "Glyphs: #{font.glyph_count}"
```

## CharStrings

```ruby
# Type 1 CharStrings use operators
# hstem, vstem, moveto, lineto, curveto, etc.

font.charstrings.each do |glyph_name, charstring|
  puts "#{glyph_name}: #{charstring.length} bytes"
end
```

## seac Composites

Type 1 supports composite characters via `seac`:

```
# Example: é = e + acute accent
# seac references two glyphs by name
```

When converting to CFF, seac must be expanded (CFF doesn't support it).

## Converting

### Type 1 to OTF

```bash
fontisan convert font.pfb --to otf --output font.otf
```

### Type 1 to TTF

```bash
fontisan convert font.pfb --to ttf --output font.ttf
```

### With Unicode Generation

```bash
# Generate Unicode mappings from glyph names
fontisan convert font.pfb --to otf --generate-unicode --output font.otf
```

## Characteristics

### Advantages

- **Print workflows** — PostScript native
- **High quality** — Professional fonts
- **Cubic curves** — Fewer points

### Limitations

- **Legacy format** — Modern systems prefer OTF
- **Limited Unicode** — Requires glyph name mapping
- **No native Unicode** — Must be generated

## seac Expansion

seac (Standard Encoding Accented Character) must be expanded for CFF:

```ruby
# Fontisan automatically expands seac during conversion
options = Fontisan::ConversionOptions.new(
  opening: { decompose_composites: true }
)
```
