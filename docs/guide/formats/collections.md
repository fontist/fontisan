---
title: Font Collections
---

# Font Collections (TTC/OTC)

Font collections pack multiple fonts into a single file with shared tables.

## Overview

| Format | Description | Font Type |
|--------|-------------|-----------|
| TTC | TrueType Collection | TrueType fonts |
| OTC | OpenType Collection | CFF/OpenType fonts |

## Benefits

- **Smaller total size** — Shared tables
- **Simpler distribution** — One file
- **Family organization** — Related fonts together

## Shared Tables

Collections share common tables:

- `cmap` — Character mappings
- `loca` — Glyph locations
- `maxp` — Maximum profile
- `name` — Font names
- `post` — PostScript names

## Listing Fonts

### CLI

```bash
fontisan ls family.ttc

# Collection: family.ttc
# Fonts: 4
#
# 0. Family Regular
#    PostScript: Family-Regular
#    Glyphs: 268, Tables: 14
#
# 1. Family Bold
#    PostScript: Family-Bold
#    Glyphs: 268, Tables: 14
```

### API

```ruby
collection = Fontisan::FontLoader.load('family.ttc')

collection.each_with_index do |font, index|
  puts "#{index}. #{font.family_name} #{font.style}"
end
```

## Extracting Fonts

### CLI

```bash
# Extract all fonts
fontisan unpack family.ttc --output-dir ./extracted

# Extract specific font
fontisan unpack family.ttc --index 0 --output regular.ttf

# Extract with conversion
fontisan unpack family.ttc --output-dir ./otf --format otf
```

### API

```ruby
collection = Fontisan::FontLoader.load('family.ttc')

collection.each_with_index do |font, index|
  output = "font-#{index}.ttf"
  Fontisan::FontWriter.write(font, output)
end
```

## Creating Collections

### CLI

```bash
# Pack fonts into TTC
fontisan pack regular.ttf bold.ttf italic.ttf --output family.ttc

# Pack with deduplication
fontisan pack *.ttf --output family.ttc --deduplicate

# Pack as OTC
fontisan pack regular.otf bold.otf --output family.otc
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

## Table Deduplication

```bash
# Deduplicate tables when packing
fontisan pack *.ttf --output family.ttc --deduplicate
```

Benefits:
- Smaller file size
- Identical tables shared
- Optimized storage

## Converting Collections

### TTC to OTC

```bash
fontisan convert family.ttc --to otc --output family.otc
```

### OTC to TTC

```bash
fontisan convert family.otc --to ttc --output family.ttc
```

## Apple dfont

dfont supports mixed font types:

```bash
# Convert TTC to dfont
fontisan convert family.ttc --to dfont --output family.dfont
```
