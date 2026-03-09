# Font Hinting

Fontisan provides tools for working with font hinting data.

## Overview

Font hinting (also known as instructing) is the process of adjusting the display of fonts to align with a pixel grid, improving legibility at small sizes.

## Hinting Formats

- **fpgm/cvt/prep** - TrueType instructions
- **gasp** - Grid-fitting and scan-conversion procedure
- **GPOS/GSUB** - OpenType positioning and substitution

## Reading Hinting Data

```ruby
require 'fontisan'

font = Fontisan.load('font.ttf')

# Check for TrueType instructions
if font.trueType_instructions?
  puts "Font has TrueType hinting"
end

# Get gasp table
if font.gasp_table
  font.gasp_table.ranges.each do |range|
    puts "Size #{range.range_max_ppem}: #{range.behavior}"
  end
end
```

## Auto-Hinting

```ruby
# Apply auto-hinting
Fontisan.autohint('font.ttf', output: 'font-hinted.ttf')
```

## Related

- [Font Conversion](/guide/conversion) - Convert fonts while preserving hinting
