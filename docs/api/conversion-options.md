---
title: ConversionOptions
---

# ConversionOptions

Type-safe conversion configuration.

## Overview

`Fontisan::ConversionOptions` provides a type-safe way to configure font conversions.

## Class Methods

### recommended(from:, to:)

Get recommended options for a conversion type.

```ruby
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)
# => #<Fontisan::ConversionOptions ...>

# Access settings
options.opening   # => { convert_curves: true, ... }
options.generating # => { hinting_mode: "auto", ... }
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| from | Symbol | Source format |
| to | Symbol | Target format |

### from_preset(name)

Load options from a named preset.

```ruby
# Web optimization preset
options = Fontisan::ConversionOptions.from_preset(:web_optimized)

# Type 1 to modern
options = Fontisan::ConversionOptions.from_preset(:type1_to_modern)
```

**Available Presets:**

| Preset | From | To |
|--------|------|-----|
| `type1_to_modern` | Type 1 | OTF |
| `modern_to_type1` | OTF | Type 1 |
| `web_optimized` | OTF | WOFF2 |
| `archive_to_modern` | TTC | OTF |

### new(**kwargs)

Create custom options.

```ruby
options = Fontisan::ConversionOptions.new(
  from: :ttf,
  to: :otf,
  opening: {
    convert_curves: true,
    autohint: true
  },
  generating: {
    hinting_mode: 'auto',
    optimize_tables: true
  }
)
```

## Instance Attributes

### opening

Opening options control source font processing.

| Option | Type | Default |
|--------|------|---------|
| `decompose_composites` | Boolean | false |
| `convert_curves` | Boolean | true |
| `scale_to_1000` | Boolean | false |
| `scale_from_1000` | Boolean | false |
| `autohint` | Boolean | false |
| `generate_unicode` | Boolean | false |
| `store_custom_tables` | Boolean | true |
| `store_native_hinting` | Boolean | false |
| `interpret_ot` | Boolean | false |
| `read_all_records` | Boolean | false |
| `preserve_encoding` | String | nil |

### generating

Generating options control output font writing.

| Option | Type | Default |
|--------|------|---------|
| `write_pfm` | Boolean | false |
| `write_afm` | Boolean | false |
| `write_inf` | Boolean | false |
| `select_encoding_automatically` | Boolean | false |
| `hinting_mode` | String | 'preserve' |
| `decompose_on_output` | Boolean | false |
| `write_custom_tables` | Boolean | true |
| `optimize_tables` | Boolean | false |
| `compression` | String | nil |
| `transform_tables` | Boolean | false |
| `preserve_metadata` | Boolean | true |

## Examples

### Basic Conversion

```ruby
options = Fontisan::ConversionOptions.recommended(from: :ttf, to: :otf)
converter = Fontisan::Converters::OutlineConverter.new
result = converter.convert(font, options: options)
```

### Web Optimization

```ruby
options = Fontisan::ConversionOptions.from_preset(:web_optimized)
Fontisan::FontWriter.write(font, 'output.woff2', options: options)
```

### Custom Options

```ruby
options = Fontisan::ConversionOptions.new(
  opening: { autohint: true },
  generating: {
    hinting_mode: 'auto',
    optimize_tables: true,
    compression: 'brotli'
  }
)
```
