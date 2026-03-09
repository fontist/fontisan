---
title: Type 1 to Modern Formats
---

# Type 1 to Modern Formats

Adobe Type 1 fonts (PFB/PFA) are legacy PostScript fonts. Fontisan provides comprehensive support for converting them to modern formats.

## Overview

Type 1 fonts use:
- **Cubic Bézier curves** — Compatible with CFF/OpenType
- **PostScript hints** — Different from TrueType instructions
- **Custom encoding** — May lack Unicode mappings

## Type 1 → OTF

Convert Type 1 fonts to OpenType/CFF format.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :type1, to: :otf)
# Returns:
# opening: { decompose_composites: false, generate_unicode: true }
# generating: { hinting_mode: "none", decompose_on_output: true }
```

### CLI

```bash
# Basic conversion
fontisan convert font.pfb --to otf --output font.otf

# With preset
fontisan convert font.pfb --to otf --preset type1_to_modern --output font.otf

# With Unicode generation
fontisan convert font.pfb --to otf --generate-unicode --output font.otf
```

### Key Considerations

- **Unicode**: Generated from Adobe Glyph List
- **CharStrings**: Type 1 → CFF format (direct conversion)
- **Hinting**: PostScript hints preserved in CFF
- **seac composites**: Must be expanded (CFF doesn't support seac)

## Type 1 → TTF

Convert Type 1 fonts to TrueType format.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :type1, to: :ttf)
# Returns:
# opening: { decompose_composites: false, generate_unicode: true }
# generating: { hinting_mode: "full" }
```

### Workflow

```
Type 1 → CFF (OTF) → TTF
```

### Key Considerations

- Two-step conversion compounds approximation errors
- Curve conversion: CFF cubic → TrueType quadratic
- Unicode: Generated from glyph names

### CLI

```bash
fontisan convert font.pfb --to ttf --autohint --output font.ttf
```

## OTF → Type 1

Convert OpenType fonts back to Type 1 for legacy systems.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :otf, to: :type1)
# opening: { decompose_composites: false }
# generating: { write_pfm: true, write_afm: true, write_inf: true,
#              select_encoding_automatically: true, hinting_mode: "preserve",
#              decompose_on_output: false }
```

### CLI

```bash
fontisan convert font.otf --to type1 --output font.pfb
```

### Limitations

- Reverse conversion from CFF to Type 1
- Modern OpenType features (GPOS, GSUB variations) lost in Type 1
- CFF hints may not translate exactly to Type 1 hints

## Type 1 → Type 1 (Copy)

Re-encode Type 1 font or regenerate metrics files.

### Recommended Options

```ruby
Fontisan::ConversionOptions.recommended(from: :type1, to: :type1)
# opening: { decompose_composites: false, generate_unicode: true }
# generating: { write_pfm: true, write_afm: true, write_inf: true,
#              select_encoding_automatically: true, hinting_mode: "preserve" }
```

### CLI

```bash
# Regenerate metrics files
fontisan convert font.pfb --to type1 --write-pfm --write-afm --output font-copy.pfb
```

## seac Composite Handling

Type 1 fonts use `seac` (Standard Encoding Accented Character) for composite glyphs. CFF doesn't support seac, so these must be expanded.

```ruby
# seac composites are automatically decomposed
options = Fontisan::ConversionOptions.new(
  opening: { decompose_composites: true }
)
```

### What seac Does

```
# seac combines two glyphs:
# Example: é = e + ´ (acute accent)
#
# In Type 1:
# /eacute { seac (e) (acute) } def
#
# In CFF/OTF:
# Must be expanded to actual outlines
```

## Presets

### type1_to_modern

Optimize Type 1 fonts for modern use:

```ruby
Fontisan::ConversionOptions.from_preset(:type1_to_modern)
# From: :type1, To: :otf
# opening: { generate_unicode: true, decompose_composites: false }
# generating: { hinting_mode: "preserve", decompose_on_output: true }
```

Use cases:
- Modernizing legacy Type 1 fonts
- Preparing fonts for web use
- Converting fonts for modern applications

### modern_to_type1

Convert modern fonts back to Type 1:

```ruby
Fontisan::ConversionOptions.from_preset(:modern_to_type1)
# From: :otf, To: :type1
# opening: { convert_curves: true, scale_to_1000: true,
#           autohint: true, decompose_composites: false,
#           store_custom_tables: false }
# generating: { write_pfm: true, write_afm: true, write_inf: true,
#              select_encoding_automatically: true,
#              hinting_mode: "preserve" }
```

Use cases:
- Legacy system compatibility
- Font distribution for older applications
- Working with Type 1 workflows

## Examples

### Convert Type 1 to Web Font

```bash
# Direct to WOFF2
fontisan convert font.pfb --to woff2 --output font.woff2 --preset type1_to_modern

# With custom options
fontisan convert font.pfb --to woff2 --output font.woff2 \
  --generate-unicode --optimize-tables
```

### Batch Convert Directory

```ruby
Dir.glob('legacy/*.pfb').each do |input|
  output = input.sub('.pfb', '.otf').sub('legacy/', 'modern/')
  Fontisan.convert(input, output_format: :otf, output_path: output)
end
```
