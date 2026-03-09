---
title: Migrate from fonttools
---

# Migrate from fonttools (Python)

This guide helps you migrate from Python's fonttools library to Fontisan.

## Overview

| fonttools (Python) | Fontisan (Ruby) |
|--------------------|-----------------|
| Python required | Pure Ruby |
| Native extensions | Pure Ruby |
| No validation | Built-in validation |
| Partial Type 1 | Full Type 1 support |

## Quick Reference

### Loading Fonts

```python
# fonttools
from fontTools.ttLib import TTFont
font = TTFont('font.ttf')
```

```ruby
# Fontisan
font = Fontisan::FontLoader.load('font.ttf')
```

### Saving Fonts

```python
# fonttools
font.save('output.ttf')
```

```ruby
# Fontisan
Fontisan::FontWriter.write(font, 'output.ttf')
```

### TTX Export

```bash
# fonttools
ttx font.ttf

# Fontisan
fontisan export font.ttf --format ttx --output font.ttx
```

## Command Equivalents

### ttx

| fonttools | Fontisan |
|-----------|----------|
| `ttx font.ttf` | `fontisan export font.ttf --format ttx` |
| `ttx -t name font.ttf` | `fontisan export font.ttf --format ttx --tables name` |
| `ttx -o output.ttx font.ttf` | `fontisan export font.ttf --format ttx --output output.ttx` |

### fonttools subset

| fonttools | Fontisan |
|-----------|----------|
| `fonttools subset font.ttf --text="ABC"` | `fontisan subset font.ttf --chars "ABC"` |
| `fonttools subset font.ttf --unicodes="U+0041"` | `fontisan subset font.ttf --unicodes "U+0041"` |
| `fonttools subset font.ttf --output-file=out.ttf` | `fontisan subset font.ttf --output out.ttf` |

## API Migration

### Access Tables

```python
# fonttools
name_table = font['name']
family = name_table.getBestFamilyName()
```

```ruby
# Fontisan
name_table = font.tables['name']
family = name_table.family_name
```

### Get Glyph Count

```python
# fonttools
num_glyphs = font['maxp'].numGlyphs
```

```ruby
# Fontisan
num_glyphs = font.tables['maxp'].num_glyphs
```

### Iterate Glyphs

```python
# fonttools
for glyph_name in font.getGlyphOrder():
    print(glyph_name)
```

```ruby
# Fontisan
font.glyphs.each_with_index do |glyph, id|
  puts font.glyph_name(id)
end
```

### Variable Fonts

```python
# fonttools
axes = font['fvar'].axes
for axis in axes:
    print(axis.axisTag, axis.minValue, axis.maxValue)
```

```ruby
# Fontisan
fvar = font.tables['fvar']
fvar.axes.each do |axis|
  puts "#{axis.tag}: #{axis.min_value} - #{axis.max_value}"
end
```

### Generate Instance

```python
# fonttools
from fontTools.varLib.instancer import instantiateVariableFont
instance = instantiateVariableFont(font, {'wght': 700})
```

```ruby
# Fontisan
writer = Fontisan::Variation::InstanceWriter.new(font)
instance = writer.generate_instance(wght: 700)
```

## Feature Comparison

| Feature | fonttools | Fontisan |
|---------|-----------|----------|
| Pure Ruby | ❌ | ✅ |
| Python-free | ❌ | ✅ |
| TTF/OTF support | ✅ | ✅ |
| WOFF/WOFF2 | ✅ | ✅ |
| Type 1 support | Partial | ✅ |
| Variable fonts | ✅ | ✅ |
| Font validation | ❌ | ✅ |
| Hint conversion | ❌ | ✅ |
| Collections | ✅ | ✅ |
| UFO format | ✅ | Planned |
| FEA parsing | ✅ | ❌ |
| Designspace | ✅ | ❌ |

## Advantages of Fontisan

### Pure Ruby

- No Python installation required
- No native extension compilation
- Works in Ruby-only environments
- Easy deployment

### Built-in Validation

```ruby
# Fontisan has validation built-in
result = Fontisan.validate('font.ttf', profile: :production)
puts result.valid?
```

### Bidirectional Hint Conversion

```ruby
# Convert hints between TrueType and PostScript
fontisan convert font.ttf --to otf --hinting-mode preserve
```

### Type 1 Support

```ruby
# Full Type 1 support including conversion
fontisan convert font.pfb --to otf --output font.otf
```

## Migration Checklist

1. [ ] Install Fontisan: `gem install fontisan`
2. [ ] Replace `from fontTools.ttLib import TTFont` with `require 'fontisan'`
3. [ ] Replace `TTFont(path)` with `Fontisan::FontLoader.load(path)`
4. [ ] Replace `font.save(path)` with `Fontisan::FontWriter.write(font, path)`
5. [ ] Update table access from `font['name']` to `font.tables['name']`
6. [ ] Test your workflow

## Getting Help

- [Fontisan Guide](/guide/)
- [API Reference](/api/)
- [GitHub Issues](https://github.com/fontist/fontisan/issues)
