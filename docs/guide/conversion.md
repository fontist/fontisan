# Font Conversion

Fontisan supports conversion between various font formats.

## Supported Formats

| Input | Output Formats |
|-------|---------------|
| TrueType (.ttf) | OTF, WOFF, WOFF2 |
| OpenType (.otf) | TTF, WOFF, WOFF2 |
| Type 1 (.pfb) | TTF, OTF, WOFF, WOFF2 |
| WOFF | TTF, OTF |
| WOFF2 | TTF, OTF |

## Basic Conversion

```ruby
require 'fontisan'

# Convert TTF to WOFF2
Fontisan.convert('font.ttf', output_format: :woff2)

# Convert with custom output path
Fontisan.convert('font.ttf', output_path: 'output/font.woff2')
```

## Batch Conversion

```ruby
# Convert multiple files
fonts = Dir.glob('fonts/*.ttf')
fonts.each do |font|
  Fontisan.convert(font, output_format: :otf)
end
```

## Related

- [WOFF/WOFF2 Formats](/guide/woff) - Details on web font formats
