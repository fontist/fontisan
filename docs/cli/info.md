---
title: info
---

# info

Get comprehensive font information.

## Quick Reference

```bash
fontisan info <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--brief` | Fast mode - essential metadata only (5x faster) |
| `--verbose` | Show all available information |
| `--tables` | Include table listing |
| `--features` | Include OpenType features |

## Brief Mode

For font indexing systems that need to scan thousands of fonts quickly, use the `--brief` flag to get essential metadata only.

### Performance Benefits

- **5x faster** than full mode by using metadata-only loading
- **Loads only 6 tables** instead of 15-20 (name, head, hhea, maxp, OS/2, post)
- **Lower memory usage** through reduced table loading
- **Optimized for batch processing** of many fonts

### Brief Mode Attributes

Brief mode populates only the following 13 essential attributes:

**Font Identification:**
- `font_format` - Font format (truetype, cff)
- `is_variable` - Whether font is variable

**Essential Names:**
- `family_name` - Font family name
- `subfamily_name` - Font subfamily/style
- `full_name` - Full font name
- `postscript_name` - PostScript name

**Version Info:**
- `version` - Version string

**Metrics:**
- `font_revision` - Font revision number
- `units_per_em` - Units per em

**Vendor:**
- `vendor_id` - Vendor/foundry ID

### Brief Mode Examples

```bash
# Fast font indexing
fontisan info font.ttf --brief

# Brief mode with JSON output
fontisan info font.ttf --brief --format json

# Process many fonts quickly
for font in *.ttf; do
  fontisan info "$font" --brief --format json >> fonts.jsonl
done
```

### Brief Mode Sample Output

```
Font type:                TrueType (Variable)
Family:                   Mona Sans ExtraLight
Subfamily:                Regular
Full name:                Mona Sans ExtraLight
PostScript name:          MonaSans-ExtraLight
Version:                  Version 2.001
Vendor ID:                GTHB
Font revision:            2.00101
Units per em:             1000
```

### Brief Mode JSON Output

```json
{
  "font_format": "truetype",
  "is_variable": true,
  "family_name": "Mona Sans ExtraLight",
  "subfamily_name": "Regular",
  "full_name": "Mona Sans ExtraLight",
  "postscript_name": "MonaSans-ExtraLight",
  "version": "Version 2.001",
  "font_revision": 2.00101,
  "vendor_id": "GTHB",
  "units_per_em": 1000
}
```

## Full Mode

Full mode populates additional attributes (remain `nil` in brief mode):

- `postscript_cid_name`, `preferred_family`, `preferred_subfamily`, `mac_font_menu_name`
- `unique_id`, `description`, `designer`, `designer_url`
- `manufacturer`, `vendor_url`, `trademark`, `copyright`
- `license_description`, `license_url`, `sample_text`, `permissions`

## Output

Shows comprehensive font metadata:
- Family and style names
- Version and copyright
- PostScript name
- Format (TrueType, OpenType, etc.)
- Glyph count
- Table count
- Unicode ranges
- Variable font axes (if applicable)

## Examples

```bash
# Basic info
fontisan info font.ttf

# Brief mode for fast indexing
fontisan info font.ttf --brief

# Verbose output
fontisan info font.ttf --verbose

# Include tables
fontisan info font.ttf --tables

# JSON output
fontisan info font.ttf --format json
```

## Sample Output

```
Font: SourceSans3-Regular.otf
Format: OpenType (CFF)
Family: Source Sans 3
Style: Regular
PostScript: SourceSans3-Regular
Version: 3.046
Copyright: Copyright 2023 Adobe

Glyphs: 1,024
Tables: 18
Characters: 892

Unicode Ranges:
  Basic Latin (95)
  Latin-1 Supplement (96)
  Latin Extended-A (128)
  Greek and Coptic (72)

Features: 24
  liga, dlig, kern, mark, mkmk, ...
```

## Use Cases

### Get Family Name

```bash
fontisan info font.ttf --format json | jq '.family_name'
```

### Check Font Format

```bash
fontisan info font.ttf --format json | jq '.format'
```

### Compare Fonts

```bash
diff <(fontisan info font1.ttf) <(fontisan info font2.ttf)
```

### Batch Process Fonts (Fast)

```bash
# Use brief mode for fast batch processing
for font in *.ttf; do
  echo "=== $font ==="
  fontisan info "$font" --brief
done
```

### Build Font Index

```bash
# Create JSON index of all fonts
echo '[' > fonts.json
first=true
for font in **/*.ttf; do
  if $first; then first=false; else echo ',' >> fonts.json; fi
  fontisan info "$font" --brief --format json >> fonts.json
done
echo ']' >> fonts.json
```

## Ruby API

### Brief Mode

```ruby
require 'fontisan'

# Fast metadata-only loading
info = Fontisan.info("font.ttf", brief: true)

# Access populated fields
puts info.family_name       # "Open Sans"
puts info.postscript_name   # "OpenSans-Regular"
puts info.is_variable       # false

# Non-essential fields are nil
puts info.copyright         # nil (not populated)
puts info.designer          # nil (not populated)

# Serialize to YAML/JSON
puts info.to_yaml
puts info.to_json
```

### Brief Mode for Collections

```ruby
require 'fontisan'

# Specify font index for TTC/OTC files
info = Fontisan.info("/path/to/fonts.ttc", brief: true, font_index: 0)
puts info.family_name
```

## Related Commands

- [tables](/cli/tables) — Detailed table information
- [glyphs](/cli/glyphs) — List all glyphs
- [features](/cli/features) — List OpenType features
- [variable](/cli/variable) — Variable font details
- [version](/cli/version) — Show Fontisan version
