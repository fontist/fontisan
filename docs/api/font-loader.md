---
title: FontLoader
---

# FontLoader

Unified font loading with automatic format detection.

## Overview

`Fontisan::FontLoader` provides a unified interface for loading fonts in any supported format.

## Class Methods

### load(source)

Load a font from file path or IO.

```ruby
# From file path
font = Fontisan::FontLoader.load('font.ttf')
font = Fontisan::FontLoader.load('font.otf')
font = Fontisan::FontLoader.load('font.pfb')
font = Fontisan::FontLoader.load('font.woff2')

# From IO
font = Fontisan::FontLoader.load(File.open('font.ttf'))

# From string
font = Fontisan::FontLoader.load(File.read('font.ttf', mode: 'rb'))
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| source | String, IO | File path, IO object, or binary data |

**Returns:** SfntFont, Type1Font, or Collection

**Raises:** Fontisan::FormatError if format is unsupported

### detect_format(path)

Detect a font's on-disk format from its content (magic bytes). The file
extension is ignored — a `.ttc` that actually contains a single OpenType-CFF
font is reported as `:otf`.

```ruby
format = Fontisan::FontLoader.detect_format('font.ttf')
# => :ttf

format = Fontisan::FontLoader.detect_format('font.otf')
# => :otf

format = Fontisan::FontLoader.detect_format('font.pfb')
# => :pfb

format = Fontisan::FontLoader.detect_format('font.pfa')
# => :pfa
```

**Returns:** Symbol (`:ttf`, `:otf`, `:ttc`, `:otc`, `:woff`, `:woff2`,
`:dfont`, `:pfa`, `:pfb`) or `nil` if the format is not recognised.

## Supported Formats

| Symbol  | Detection   | Notes                          |
|---------|-------------|--------------------------------|
| `:ttf`   | Magic bytes | TrueType                       |
| `:otf`   | Magic bytes | OpenType / CFF                 |
| `:ttc`   | Magic bytes | TrueType Collection            |
| `:otc`   | Magic bytes | OpenType Collection            |
| `:woff`  | Magic bytes | Web Open Font Format           |
| `:woff2` | Magic bytes | Web Open Font Format 2         |
| `:pfb`   | Marker byte | Adobe Type 1 Binary            |
| `:pfa`   | Text header | Adobe Type 1 ASCII             |
| `:dfont` | Magic bytes | Apple Data-Fork resource fork  |

## Examples

### Load with Error Handling

```ruby
begin
  font = Fontisan::FontLoader.load(path)
  puts "Loaded: #{font.family_name}"
rescue Fontisan::FormatError => e
  puts "Unsupported format: #{e.message}"
rescue Errno::ENOENT => e
  puts "File not found: #{path}"
end
```

### Batch Loading

```ruby
fonts = Dir.glob('fonts/*.ttf').map do |path|
  Fontisan::FontLoader.load(path)
end

puts "Loaded #{fonts.length} fonts"
```

### Detect and Load

```ruby
path = 'unknown.dat'

format = Fontisan::FontLoader.detect_format(path)
if format
  puts "Detected format: #{format}"
  font = Fontisan::FontLoader.load(path)
else
  puts "Unknown format"
end
```
