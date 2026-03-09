---
title: API Reference
---

# API Reference

This section provides detailed API documentation for Fontisan's core classes, converters, validators, and models.

## Core Classes

- [FontLoader](/api/font-loader) — Unified font loading with automatic format detection
- [FontWriter](/api/font-writer) — Write fonts to various formats
- [ConversionOptions](/api/conversion-options) — Type-safe conversion configuration
- [SfntFont](/api/sfnt-font) — Base class for TrueType/OpenType fonts
- [Type1Font](/api/type1-font) — Adobe Type 1 font handler

## Converters

- [OutlineConverter](/api/converters/outline-converter) — TTF ↔ OTF outline conversion
- [CurveConverter](/api/converters/curve-converter) — Quadratic ↔ Cubic curve conversion
- [HintConverter](/api/converters/hint-converter) — TrueType ↔ PostScript hint conversion

## Validators

- [FontValidator](/api/validators/font-validator) — Main validation entry point
- [ValidationProfile](/api/validators/profile) — Validation profile definitions
- [ValidationHelper](/api/validators/helper) — Individual validation helpers

## Models

- [Glyph](/api/models/glyph) — Font glyph representation
- [GlyphAccessor](/api/models/glyph-accessor) — Unified glyph access with caching
- [TableAnalyzer](/api/models/table-analyzer) — Font table analysis

## Using the API

### Loading Fonts

```ruby
require 'fontisan'

# Automatic format detection
font = Fontisan::FontLoader.load('font.ttf')
font = Fontisan::FontLoader.load('font.otf')
font = Fontisan::FontLoader.load('font.pfb')

# Load from IO
font = Fontisan::FontLoader.load(io)
```

### Converting Fonts

```ruby
# Get recommended options
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)

# Convert with options
converter = Fontisan::Converters::OutlineConverter.new
tables = converter.convert(font, options: options)

# Write the result
Fontisan::FontWriter.write(font, 'output.otf')
```

### Validating Fonts

```ruby
# Validate with a profile
result = Fontisan::FontValidator.validate('font.ttf', profile: :google_fonts)

# Check results
if result.passed?
  puts "Font is valid!"
else
  result.errors.each do |error|
    puts "#{error.code}: #{error.message}"
  end
end
```
