---
title: Getting Started
---

# Getting Started

Fontisan is a font processing library for Ruby that provides tools for font conversion, validation, and manipulation.

::: warning Font License Considerations
Commercial fonts often come with restrictive licenses that may prohibit:

- **Subsetting** — Reducing the character set
- **Format conversion** — Converting between TTF, OTF, WOFF, etc.
- **Variable font instancing** — Generating static instances
- **Glyph modification** — Altering or extracting individual glyphs
- **Redistribution** — Sharing converted or modified fonts

Always check your font's End User License Agreement (EULA) before processing. Many foundries require additional licenses for web embedding, subsetting, or format conversion. **Fontisan provides the tools — you are responsible for ensuring you have the rights to use them.**
:::

## Features

Fontisan provides comprehensive font processing capabilities:

- **🔄 Font Conversion** — Convert between TTF, OTF, WOFF, WOFF2, Type 1, and SVG formats
- **✅ Font Validation** — Validate fonts with 5 profiles and 56 helpers
- **📦 Type 1 Support** — Adobe Type 1 fonts (PFB/PFA) with eexec decryption
- **🎨 Color Fonts** — COLR/CPAL, sbix, and SVG color fonts
- **⚡ Variable Fonts** — Instance generation, format conversion, named instances
- **🔧 Font Hinting** — Bidirectional TrueType ↔ PostScript hint conversion
- **📚 Collections** — TTC/OTC/dfont pack, unpack, and deduplication
- **💎 Pure Ruby** — No Python, no C++, no C# dependencies

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fontisan'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install fontisan
```

## Quick Start

### Load a Font

```ruby
require 'fontisan'

# Automatic format detection
font = Fontisan::FontLoader.load('font.ttf')

# Works with any format
font = Fontisan::FontLoader.load('font.otf')    # OpenType
font = Fontisan::FontLoader.load('font.woff2')  # WOFF2
font = Fontisan::FontLoader.load('font.pfb')    # Type 1
font = Fontisan::FontLoader.load('fonts.ttc')   # Collection
```

### Get Font Information

```ruby
# Get basic info
info = Fontisan::Commands::InfoCommand.new(font: font).run
puts info.family_name
puts info.style
puts info.version

# Get table information
tables = font.tables
puts tables.keys
```

### Convert Fonts

```ruby
# Simple conversion
Fontisan.convert('input.ttf', output_format: :woff2)

# With custom options
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: { autohint: true, convert_curves: true }
)
Fontisan.convert('input.ttf', output_format: :otf, options: options)
```

### Validate Fonts

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

## CLI Usage

Fontisan includes a comprehensive CLI:

```bash
# Get font information
fontisan info font.ttf

# List fonts in a collection
fontisan ls fonts.ttc

# Convert fonts
fontisan convert input.ttf --to otf --output output.otf

# Validate fonts
fontisan validate font.ttf --profile google_fonts

# Extract fonts from collection
fontisan unpack fonts.ttc --output-dir ./extracted

# Pack fonts into collection
fontisan pack font1.ttf font2.ttf --output fonts.ttc

# Export to TTX
fontisan export font.ttf --format ttx

# Subset fonts
fontisan subset font.ttf --chars "ABC123"
```

## Next Steps

- [Installation Details](/guide/installation) — Detailed installation options
- [Quick Start Guide](/guide/quick-start) — Common workflows
- [CLI Reference](/guide/cli/) — Command-line documentation
- [Font Formats](/guide/formats/) — Supported format details
- [Conversion Guide](/guide/conversion/) — Conversion options and best practices
