# Variable Fonts

Fontisan provides tools for working with OpenType variable fonts.

## Overview

Variable fonts (OpenType Font Variations) allow a single font file to contain multiple variations along design axes (weight, width, slant, etc.).

## Reading Variable Fonts

```ruby
require 'fontisan'

# Load a variable font
font = Fontisan.load('variable-font.ttf')

# Check if font is variable
if font.variable?
  puts "This is a variable font"
end
```

## Font Axes

```ruby
# Get available axes
font.axes.each do |axis|
  puts "#{axis.tag}: #{axis.name}"
  puts "  Range: #{axis.min} - #{axis.max}"
  puts "  Default: #{axis.default}"
end
```

## Named Instances

```ruby
# Get named instances
font.named_instances.each do |instance|
  puts "#{instance.name}:"
  instance.coordinates.each do |tag, value|
    puts "  #{tag}: #{value}"
  end
end
```

## Working with Variations

```ruby
# Create a variation
variation = font.variation('wght' => 700, 'wdth' => 100)

# Export as static font
variation.export('font-bold.ttf')
```

## Related

- [Color Fonts](/guide/color) - Color font support
