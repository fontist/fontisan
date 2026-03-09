---
title: pack/unpack
---

# pack/unpack

Work with font collections — TTC, OTC, and dfont formats that contain multiple fonts in a single file.

## What are Font Collections?

Font collections bundle multiple related fonts together:

| Format | Description | Extension |
|--------|-------------|-----------|
| TTC | TrueType Collection | `.ttc` |
| OTC | OpenType Collection (CFF) | `.otc` or `.ttc` |
| dfont | Apple Data Fork Font | `.dfont` |

Collections save space by sharing common tables (like glyph outlines) across fonts. They're commonly used for font families.

## pack

Create a font collection from multiple individual fonts.

```bash
fontisan pack <fonts...> --output <collection>
```

### Options

| Option | Description |
|--------|-------------|
| `--output FILE` | Output collection file (.ttc or .otc) |
| `--deduplicate` | Share common tables to reduce size |
| `--format TYPE` | Collection type (ttc or otc) |

### Examples

```bash
# Create a collection from a font family
fontisan pack Regular.ttf Bold.ttf Italic.ttf --output Family.ttc

# Create with table deduplication (smaller file)
fontisan pack *.ttf --output fonts.ttc --deduplicate

# Create an OpenType collection (CFF fonts)
fontisan pack Regular.otf Bold.otf --output fonts.otc
```

## unpack

Extract individual fonts from a collection.

```bash
fontisan unpack <collection> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--output-dir DIR` | Output directory for extracted fonts |
| `--format FORMAT` | Convert to format (ttf, otf, woff, woff2) |
| `--index N` | Extract only the font at index N |
| `--font-index N` | Alias for --index |

### Examples

```bash
# List and extract all fonts
fontisan unpack fonts.ttc --output-dir ./extracted

# Extract and convert to web formats in one step
fontisan unpack fonts.ttc --output-dir ./web --format woff2

# Extract a specific font by index
fontisan unpack fonts.ttc --index 0 --output Regular.ttf

# Extract from Apple dfont
fontisan unpack fonts.dfont --output-dir ./extracted
```

## Common Workflows

### Extract Collection for Web Use

```bash
# Extract and convert to WOFF2 in one command
fontisan unpack family.ttc --output-dir ./web-fonts --format woff2
```

### Extract, Modify, and Repack

```bash
# 1. Extract all fonts
fontisan unpack family.ttc --output-dir ./working

# 2. Modify fonts (e.g., subset, convert)
fontisan subset ./working/Regular.ttf --chars "ABC..." --output Regular-subset.ttf

# 3. Repack into new collection
fontisan pack *-subset.ttf --output family-subset.ttc --deduplicate
```

### Convert Collection Format

```bash
# Extract from dfont, repack as TTC
fontisan unpack fonts.dfont --output-dir ./temp
fontisan pack ./temp/*.ttf --output fonts.ttc
```

### View Collection Contents

```bash
# List fonts in a collection
fontisan ls fonts.ttc

# Get detailed info
fontisan info fonts.ttc
```

## Detailed Documentation

For comprehensive documentation including table sharing analysis and advanced options, see the [pack/unpack command guide](/guide/cli/pack).
