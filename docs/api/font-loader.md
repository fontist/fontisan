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

### detect_format(source)

Detect font format without loading.

```ruby
format = Fontisan::FontLoader.detect_format('font.ttf')
# => :ttf

format = Fontisan::FontLoader.detect_format('font.otf')
# => :otf

format = Fontisan::FontLoader.detect_format('font.pfb')
# => :type1
```

**Returns:** Symbol or nil

## Supported Formats

| Format | Detection | Notes |
|--------|-----------|-------|
| TTF | Magic number | TrueType |
| OTF | Magic number | OpenType/CFF |
| TTC | Magic number | TrueType Collection |
| OTC | Magic number | OpenType Collection |
| WOFF | Magic number | Web Open Font Format |
| WOFF2 | Magic number | Web Open Font Format 2 |
| PFB | Marker byte | Adobe Type 1 Binary |
| PFA | Text | Adobe Type 1 ASCII |
| dfont | Magic number | Apple Data Fork |

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
