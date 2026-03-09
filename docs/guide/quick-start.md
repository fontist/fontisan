---
title: Quick Start
---

# Quick Start

This guide covers the most common Fontisan workflows.

## Loading Fonts

Fontisan automatically detects font formats:

```ruby
require 'fontisan'

# TrueType
font = Fontisan::FontLoader.load('font.ttf')

# OpenType
font = Fontisan::FontLoader.load('font.otf')

# WOFF/WOFF2
font = Fontisan::FontLoader.load('font.woff')
font = Fontisan::FontLoader.load('font.woff2')

# Type 1
font = Fontisan::FontLoader.load('font.pfb')
font = Fontisan::FontLoader.load('font.pfa')

# Collections
fonts = Fontisan::FontLoader.load('fonts.ttc')
fonts = Fontisan::FontLoader.load('fonts.otc')
```

## Font Information

### Basic Information

```ruby
font = Fontisan::FontLoader.load('font.ttf')

# Access tables directly
name_table = font.tables['name']
head_table = font.tables['head']

# Get family name
family = name_table.family_name

# Get style
style = name_table.subfamily_name

# Get metrics
units_per_em = head_table.units_per_em
```

### Using CLI

```bash
# Get comprehensive info
fontisan info font.ttf

# Output in different formats
fontisan info font.ttf --format yaml
fontisan info font.ttf --format json
```

## Font Conversion

### Basic Conversion

```ruby
# TTF to OTF
Fontisan.convert('input.ttf', output_format: :otf)

# OTF to WOFF2
Fontisan.convert('input.otf', output_format: :woff2)

# Type 1 to OTF
Fontisan.convert('input.pfb', output_format: :otf)
```

### With Options

```ruby
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: { autohint: true, convert_curves: true },
  generating: { hinting_mode: 'auto' }
)

Fontisan.convert('input.ttf', output_format: :otf, options: options)
```

### Using CLI

```bash
# Basic conversion
fontisan convert input.ttf --to otf --output output.otf

# Show recommended options
fontisan convert input.ttf --to otf --show-options

# Use a preset
fontisan convert font.pfb --to otf --preset type1_to_modern --output output.otf

# With autohint
fontisan convert input.ttf --to otf --autohint --hinting-mode auto --output output.otf
```

## Font Validation

### Using Ruby API

```ruby
# Validate with default profile
result = Fontisan::FontValidator.validate('font.ttf')

# Validate with specific profile
result = Fontisan::FontValidator.validate('font.ttf', profile: :google_fonts)

# Check results
if result.passed?
  puts "✓ Font is valid"
else
  puts "✗ Validation failed:"
  result.errors.each do |error|
    puts "  - #{error.code}: #{error.message}"
  end
end
```

### Using CLI

```bash
# Validate with Google Fonts profile
fontisan validate font.ttf --profile google_fonts

# Validate with Microsoft profile
fontisan validate font.ttf --profile microsoft

# Validate multiple files
fontisan validate fonts/*.ttf --profile production
```

## Working with Collections

### List Fonts in Collection

```bash
fontisan ls fonts.ttc
```

### Extract Fonts from Collection

```bash
# Extract all fonts
fontisan unpack fonts.ttc --output-dir ./extracted

# Extract with format conversion
fontisan unpack fonts.ttc --output-dir ./extracted --format otf
```

### Create Collection

```bash
# Pack fonts into TTC
fontisan pack font1.ttf font2.ttf font3.ttf --output fonts.ttc

# Pack with deduplication
fontisan pack font1.ttf font2.ttf --output fonts.ttc --deduplicate
```

## Variable Fonts

### Get Axis Information

```ruby
font = Fontisan::FontLoader.load('variable-font.ttf')
fvar = font.tables['fvar']

fvar.axes.each do |axis|
  puts "#{axis.tag}: #{axis.min_value} - #{axis.max_value}"
end
```

### Generate Instance

```ruby
# Generate static instance
instance = Fontisan::Variation::InstanceGenerator.new(font).generate(
  'wght' => 700,
  'ital' => 1
)

Fontisan::FontWriter.write(instance, 'bold-italic.ttf')
```

## Next Steps

- [Font Formats](/guide/formats/) — Detailed format documentation
- [Conversion Guide](/guide/conversion/) — Advanced conversion options
- [Validation](/guide/validation/) — Validation profiles and helpers
- [CLI Reference](/guide/cli/) — Complete CLI documentation
