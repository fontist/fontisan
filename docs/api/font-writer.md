---
title: FontWriter
---

# FontWriter

Write fonts to various formats.

## Overview

`Fontisan::FontWriter` handles saving fonts to files in various formats.

## Class Methods

### write(font, path, options: {})

Write a font to a file.

```ruby
font = Fontisan::FontLoader.load('input.ttf')

# Write as TTF
Fontisan::FontWriter.write(font, 'output.ttf')

# Write as OTF
Fontisan::FontWriter.write(font, 'output.otf')

# Write as WOFF2
Fontisan::FontWriter.write(font, 'output.woff2')

# With options
options = Fontisan::ConversionOptions.new(
  generating: { optimize_tables: true }
)
Fontisan::FontWriter.write(font, 'output.ttf', options: options)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| font | SfntFont, Type1Font | Font object |
| path | String | Output file path |
| options | ConversionOptions | Optional settings |

**Returns:** Boolean

### write_to_file(data, path, sfnt_version: nil)

Write raw font data to a file.

```ruby
# Write raw table data
Fontisan::FontWriter.write_to_file(
  font.table_data,
  'output.ttf',
  sfnt_version: 0x00010000
)
```

## Output Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| TTF | .ttf | TrueType |
| OTF | .otf | OpenType/CFF |
| WOFF | .woff | Web Open Font Format |
| WOFF2 | .woff2 | Web Open Font Format 2 |
| PFB | .pfb | Adobe Type 1 |
| SVG | .svg | SVG Font |

## Examples

### Convert and Write

```ruby
# Load TTF
font = Fontisan::FontLoader.load('input.ttf')

# Convert to OTF
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)
converter = Fontisan::Converters::OutlineConverter.new
otf_tables = converter.convert(font, options: options)

# Write OTF
Fontisan::FontWriter.write(otf_tables, 'output.otf')
```

### Batch Writing

```ruby
fonts.each_with_index do |font, i|
  Fontisan::FontWriter.write(font, "output-#{i}.ttf")
end
```

### Web Optimization

```ruby
font = Fontisan::FontLoader.load('input.otf')
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
Fontisan::FontWriter.write(font, 'output.woff2', options: options)
```
