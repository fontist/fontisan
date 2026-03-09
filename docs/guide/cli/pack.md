---
title: pack/unpack
---

# pack/unpack

Create and extract font collections.

## pack

Create font collections.

### Usage

```bash
fontisan pack FONT ... --output COLLECTION [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `FONT ...` | Input font files |
| `--output PATH` | Output collection |

### Options

| Option | Description |
|--------|-------------|
| `--deduplicate` | Deduplicate tables |
| `--format FORMAT` | Collection format (ttc, otc, dfont) |

### Examples

```bash
# Create TTC
fontisan pack regular.ttf bold.ttf italic.ttf --output family.ttc

# Create OTC
fontisan pack regular.otf bold.otf --output family.otc

# With deduplication
fontisan pack *.ttf --output family.ttc --deduplicate

# Create dfont
fontisan pack regular.ttf bold.ttf --output family.dfont
```

## unpack

Extract fonts from collections.

### Usage

```bash
fontisan unpack COLLECTION [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `COLLECTION` | Collection file |

### Options

| Option | Description |
|--------|-------------|
| `--output-dir DIR` | Output directory |
| `--index N` | Extract specific font |
| `--output PATH` | Output file (with --index) |
| `--format FORMAT` | Convert to format |

### Examples

```bash
# Extract all to directory
fontisan unpack family.ttc --output-dir ./extracted

# Extract specific font
fontisan unpack family.ttc --index 0 --output regular.ttf

# Extract with conversion
fontisan unpack family.ttc --output-dir ./otf --format otf

# Extract from dfont
fontisan unpack font.dfont --output-dir ./fonts
```

## ls

List fonts in collections.

### Usage

```bash
fontisan ls COLLECTION
```

### Examples

```bash
fontisan ls family.ttc

# Collection: family.ttc
# Fonts: 4
#
# 0. Family Regular
#    PostScript: Family-Regular
#    Format: TrueType
#    Glyphs: 268, Tables: 14
#
# 1. Family Bold
#    PostScript: Family-Bold
#    Format: TrueType
#    Glyphs: 268, Tables: 14
```

## Workflow Examples

### Extract, Modify, Repack

```bash
# Extract
fontisan unpack family.ttc --output-dir ./temp

# Modify fonts...

# Repack
fontisan pack temp/*.ttf --output family-new.ttc --deduplicate
```

### Convert Collection Format

```bash
# TTC to OTC
fontisan unpack family.ttc --output-dir ./temp --format otf
fontisan pack temp/*.otf --output family.otc

# Or directly
fontisan convert family.ttc --to otc --output family.otc
```

### Analyze Collection

```bash
# List contents
fontisan ls family.ttc

# Get info
fontisan info family.ttc

# Validate all
fontisan validate family.ttc
```
