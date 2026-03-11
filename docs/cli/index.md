---
title: CLI Reference
---

# CLI Reference

Fontisan provides a comprehensive command-line interface for font processing tasks.

::: warning Font License Considerations
Commercial fonts often come with restrictive licenses that may prohibit:

- **Subsetting** — Reducing the character set
- **Format conversion** — Converting between TTF, OTF, WOFF, etc.
- **Variable font instancing** — Generating static instances
- **Glyph modification** — Altering or extracting individual glyphs
- **Redistribution** — Sharing converted or modified fonts

Always check your font's End User License Agreement (EULA) before processing. Many foundries require additional licenses for web embedding, subsetting, or format conversion. Fontisan provides the tools — you are responsible for ensuring you have the rights to use them.
:::

## Quick Reference

### Font Information Commands

| Command | Description | Example |
|---------|-------------|---------|
| `info` | Get comprehensive font information | `fontisan info font.ttf` |
| `ls` | List fonts in a collection | `fontisan ls fonts.ttc` |
| `tables` | Show font table information | `fontisan tables font.ttf` |
| `glyphs` | List glyphs with names and IDs | `fontisan glyphs font.ttf` |
| `unicode` | Show Unicode coverage | `fontisan unicode font.ttf` |
| `scripts` | List supported scripts | `fontisan scripts font.ttf` |
| `features` | List OpenType features | `fontisan features font.ttf` |
| `variable` | Show variable font axes | `fontisan variable font.ttf` |
| `optical-size` | Show optical size info | `fontisan optical-size font.ttf` |

### Font Operations

| Command | Description | Example |
|---------|-------------|---------|
| `convert` | Convert between formats | `fontisan convert input.ttf --to otf` |
| `subset` | Subset fonts | `fontisan subset font.ttf --chars "ABC"` |
| `validate` | Validate fonts | `fontisan validate font.ttf` |
| `instance` | Generate variable font instances | `fontisan instance var.ttf --wght 700` |
| `dump-table` | Extract raw table data | `fontisan dump-table font.ttf head` |

### Collection Operations

| Command | Description | Example |
|---------|-------------|---------|
| `pack` | Create font collections | `fontisan pack *.ttf -o fonts.ttc` |
| `unpack` | Extract from collections | `fontisan unpack fonts.ttc -d ./out` |

### Export Operations

| Command | Description | Example |
|---------|-------------|---------|
| `export` | Export to TTX, SVG, JSON | `fontisan export font.ttf --format ttx` |

## Global Options

```bash
fontisan [options] <command>

Options:
  --format FORMAT    Output format (text, yaml, json)
  --verbose          Verbose output
  --quiet            Suppress non-error output
  --help             Show help
  --version          Show version
```

## Getting Help

```bash
# General help
fontisan --help

# Command-specific help
fontisan convert --help
fontisan validate --help
fontisan instance --help
```

## Output Formats

Most commands support multiple output formats:

```bash
# Text (default)
fontisan info font.ttf

# YAML
fontisan info font.ttf --format yaml

# JSON
fontisan info font.ttf --format json
```

## Common Workflows

### Inspect a Font

```bash
# Basic information
fontisan info font.ttf

# Detailed table listing
fontisan tables font.ttf

# See all glyphs
fontisan glyphs font.ttf

# Check Unicode coverage
fontisan unicode font.ttf
```

### Convert for Web

```bash
# Convert single font to WOFF2
fontisan convert font.ttf --to woff2 --output font.woff2
```

### Work with Variable Fonts

```bash
# Inspect variable font axes
fontisan variable VariableFont.ttf

# Generate a specific instance
fontisan instance VariableFont.ttf --wght 700 --output Bold.ttf

# Generate multiple instances
fontisan instance VariableFont.ttf --wght 400 --output Regular.ttf
fontisan instance VariableFont.ttf --wght 700 --output Bold.ttf
```

### Work with Collections

```bash
# List fonts in collection
fontisan ls fonts.ttc

# Extract all fonts
fontisan unpack fonts.ttc --output-dir ./extracted

# Extract and convert to web formats
fontisan unpack fonts.ttc --output-dir ./web --format woff2

# Create a collection
fontisan pack Regular.ttf Bold.ttf --output Family.ttc
```

### Validate Fonts

```bash
# Quick validation
fontisan validate font.ttf

# Validate for Google Fonts
fontisan validate font.ttf --profile google_fonts

# Strict validation
fontisan validate font.ttf --profile production
```

### Export Font Data

```bash
# Export to TTX (XML format)
fontisan export font.ttf --format ttx --output font.ttx

# Export to JSON
fontisan export font.ttf --format json --output font.json

# Export specific tables
fontisan export font.ttf --format ttx --tables head,name,cmap
```

## Command Documentation

Detailed documentation for each command:

### Font Information
- [info](/cli/info) — Extract font metadata and properties (includes brief mode)
- [ls](/cli/ls) — List fonts in collections
- [tables](/cli/tables) — Show OpenType table directory
- [glyphs](/cli/glyphs) — List glyph names and indices
- [unicode](/cli/unicode) — Show Unicode character mappings
- [scripts](/cli/scripts) — List supported writing scripts
- [features](/cli/features) — List OpenType layout features
- [variable](/cli/variable) — Show variable font axes and instances
- [optical-size](/cli/optical-size) — Display optical size information

### Font Operations
- [convert](/cli/convert) — Format conversion (TTF, OTF, WOFF, WOFF2)
- [subset](/cli/subset) — Create character subsets
- [validate](/cli/validate) — Validate fonts against profiles
- [instance](/cli/instance) — Generate static instances from variable fonts
- [export](/cli/export) — Export to TTX, YAML, JSON
- [dump-table](/cli/dump-table) — Extract raw binary table data

### Collection Operations
- [pack](/cli/pack) — Create and extract font collections (TTC/OTC)

### Utilities
- [version](/cli/version) — Show Fontisan version
