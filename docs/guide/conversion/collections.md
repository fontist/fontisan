---
title: Font Collections
---

# Font Collections

Fontisan supports font collections (TTC, OTC, dfont) with pack, unpack, and format conversion capabilities.

## Overview

| Format | Description | Font Types |
|--------|-------------|------------|
| TTC | TrueType Collection | TrueType fonts only |
| OTC | OpenType Collection | CFF/OpenType fonts only |
| dfont | Apple Data Fork Font | Mixed TrueType and CFF |

## Listing Fonts in Collections

### CLI

```bash
# List fonts in a collection
fontisan ls fonts.ttc

# Output example:
# Collection: fonts.ttc
# Fonts: 2
#
# 0. Helvetica Regular
#    PostScript: Helvetica-Regular
#    Format: TrueType
#    Glyphs: 268, Tables: 14
#
# 1. Helvetica Bold
#    PostScript: Helvetica-Bold
#    Format: TrueType
#    Glyphs: 268, Tables: 14
```

### API

```ruby
collection = Fontisan::FontLoader.load('fonts.ttc')

collection.each_with_index do |font, index|
  puts "#{index}. #{font.family_name} #{font.style}"
end
```

## Extracting Fonts (Unpack)

### CLI

```bash
# Extract all fonts from collection
fontisan unpack fonts.ttc --output-dir ./extracted

# Extract specific font by index
fontisan unpack fonts.ttc --index 0 --output first.ttf

# Extract with format conversion
fontisan unpack fonts.ttc --output-dir ./extracted --format otf
```

### API

```ruby
collection = Fontisan::FontLoader.load('fonts.ttc')

collection.each_with_index do |font, index|
  output = "extracted/font-#{index}.ttf"
  Fontisan::FontWriter.write(font, output)
end
```

## Creating Collections (Pack)

### CLI

```bash
# Pack fonts into TTC
fontisan pack font1.ttf font2.ttf font3.ttf --output family.ttc

# Pack with deduplication
fontisan pack font1.ttf font2.ttf --output family.ttc --deduplicate

# Pack as OTC (OpenType collection)
fontisan pack font1.otf font2.otf --output family.otc
```

### API

```ruby
fonts = [
  Fontisan::FontLoader.load('regular.ttf'),
  Fontisan::FontLoader.load('bold.ttf'),
  Fontisan::FontLoader.load('italic.ttf')
]

Fontisan::CollectionWriter.pack(fonts, 'family.ttc')
```

## Collection Conversions

### TTC → OTC

```ruby
Fontisan::ConversionOptions.recommended(from: :ttc, to: :otc)
# opening: { convert_curves: true, decompose_composites: false, autohint: false }
# generating: { target_format: "otf", decompose_on_output: false,
#              hinting_mode: "preserve" }
```

Converts all TrueType fonts to OpenType/CFF, then repacks as OTC.

```bash
fontisan convert family.ttc --to otc --output family.otc --target-format otf
```

### OTC → TTC

```ruby
Fontisan::ConversionOptions.recommended(from: :otc, to: :ttc)
# opening: { convert_curves: true, decompose_composites: false, interpret_ot: true }
# generating: { target_format: "ttf", decompose_on_output: false,
#              hinting_mode: "auto" }
```

Converts all OpenType/CFF fonts to TrueType, then repacks as TTC.

```bash
fontisan convert family.otc --to ttc --output family.ttc --target-format ttf
```

### TTC/OTC → dfont

```ruby
Fontisan::ConversionOptions.recommended(from: :ttc, to: :dfont)
# opening: {}
# generating: { target_format: "preserve", decompose_on_output: false,
#              write_custom_tables: true }
```

Notes: dfont supports both TrueType and OpenType/CFF, or mixed formats.

```bash
fontisan convert family.ttc --to dfont --output family.dfont
```

## Table Sharing

Collections share common tables to reduce file size:

- `cmap` — Character mappings
- `loca` — Glyph locations (TrueType)
- `maxp` — Maximum profile
- `name` — Font names
- `post` — PostScript names

### Analyzing Table Sharing

```bash
fontisan info fonts.ttc

# Output includes:
# Table Sharing Statistics:
#   Shared tables: 4
#   Unique tables per font: 10
#   Space saved: 45%
```

## Deduplication

When packing collections, Fontisan can deduplicate tables:

```bash
fontisan pack font1.ttf font2.ttf --output family.ttc --deduplicate
```

### How It Works

1. Analyze all tables across fonts
2. Identify identical tables by checksum
3. Share tables where possible
4. Reduce overall file size

## Presets

### archive_to_modern

Convert font archives to modern format:

```ruby
Fontisan::ConversionOptions.from_preset(:archive_to_modern)
# From: :ttc, To: :otf
# opening: { convert_curves: true, decompose_composites: false }
# generating: { target_format: "otf", hinting_mode: "preserve" }
```

Use cases:
- Extracting fonts from TTC archives
- Standardizing collection formats
- Converting legacy font collections

## Examples

### Extract and Convert Collection

```bash
# Extract all fonts as OTF
fontisan unpack fonts.ttc --output-dir ./family --format otf

# Results in:
# family/font-0.otf
# family/font-1.otf
# family/font-2.otf
```

### Convert Collection Format

```bash
# Convert TTC to OTC
fontisan convert truetype-collection.ttc --to otc \
  --output opentype-collection.otc \
  --target-format otf \
  --hinting-mode auto
```

### Merge Multiple Collections

```ruby
# Load multiple collections
collection1 = Fontisan::FontLoader.load('set1.ttc')
collection2 = Fontisan::FontLoader.load('set2.ttc')

# Combine fonts
all_fonts = collection1.to_a + collection2.to_a

# Pack as new collection
Fontisan::CollectionWriter.pack(all_fonts, 'combined.ttc')
```

### Optimize Collection

```bash
# Pack with deduplication
fontisan pack *.ttf --output optimized.ttc --deduplicate

# Check space savings
fontisan info optimized.ttc
```
