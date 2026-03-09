# Font Validation

Fontisan provides tools to validate font files for correctness and compliance.

## Basic Validation

```ruby
require 'fontisan'

# Validate a font file
result = Fontisan.validate('font.ttf')

if result.valid?
  puts "Font is valid!"
else
  puts "Validation errors:"
  result.errors.each do |error|
    puts "  - #{error}"
  end
end
```

## Validation Options

```ruby
# Strict validation (includes optional checks)
result = Fontisan.validate('font.ttf', strict: true)

# Validate specific aspects
result = Fontisan.validate('font.ttf', checks: [:tables, :glyphs, :names])
```

## Collection Validation

For TrueType/OpenType Collections:

```ruby
# Validate a TTC file
result = Fontisan.validate_collection('fonts.ttc')

# Validate a specific font within the collection
result = Fontisan.validate_collection('fonts.ttc', index: 0)
```

## Related

- [Font Conversion](/guide/conversion) - Convert between formats
