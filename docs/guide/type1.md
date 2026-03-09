---
outline: [2, 3]
---

# Type 1 Fonts

Fontisan provides comprehensive support for Adobe Type 1 fonts.

## Overview

Adobe Type 1 fonts are a legacy format based on PostScript outlines. Fontisan can read, validate, and convert these fonts to modern formats.

## Reading Type 1 Fonts

```ruby
require 'fontisan'

# Load a Type 1 font
font = Fontisan::Type1.load('font.pfb')

# Access font properties
puts font.family_name
puts font.full_name
puts font.num_glyphs
```

## Converting Type 1 Fonts

```ruby
# Convert to TrueType
Fontisan.convert('font.pfb', output_format: :ttf)

# Convert to OpenType
Fontisan.convert('font.pfb', output_format: :otf)

# Convert to WOFF2
Fontisan.convert('font.pfb', output_format: :woff2)
```

## Handling Encodings

Type 1 fonts may use various encodings:

```ruby
font = Fontisan::Type1.load('font.pfb')

# Get the font encoding
puts font.encoding

# List available glyphs
font.glyphs.each do |glyph|
  puts "#{glyph.name}: #{glyph.codepoint}"
end
```

## Related

- [Font Conversion](/guide/conversion) - General conversion guide
