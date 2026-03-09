# Color Fonts

Fontisan supports working with color fonts in various formats.

## Supported Formats

- **COLR/CPAL** - OpenType color font tables
- **SVG** - SVG-based color fonts
- **CBDT/CBLC** - Color bitmap fonts

## Reading Color Fonts

```ruby
require 'fontisan'

# Load a color font
font = Fontisan.load('color-font.ttf')

# Check if font has color
if font.color?
  puts "This is a color font"
  puts "Format: #{font.color_format}"
end
```

## Color Palettes

For COLR/CPAL fonts:

```ruby
# Get color palettes
palettes = font.color_palettes

palettes.each do |palette|
  puts "Palette:"
  palette.colors.each do |color|
    puts "  ##{color.hex}"
  end
end
```

## Converting Color Fonts

```ruby
# Convert color font to WOFF2
Fontisan.convert('color-font.ttf', output_format: :woff2)
```

## Related

- [Variable Fonts](/guide/variable) - Variable font support
