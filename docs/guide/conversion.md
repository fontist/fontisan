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
Fontisan.convert('font.ttf', to: :woff2, output: 'font.woff2')

# Convert TTF to OTF
Fontisan.convert('font.ttf', to: :otf, output: 'font.otf')
```

## Batch Conversion

```ruby
# Convert multiple files
fonts = Dir.glob('fonts/*.ttf')
fonts.each do |font|
  out = font.sub(/\.ttf$/, '.otf')
  Fontisan.convert(font, to: :otf, output: out)
end
```

## Related

- [WOFF/WOFF2 Formats](/guide/conversion/web) - Details on web font formats
