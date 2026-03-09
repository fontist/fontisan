---
title: CLI Overview
---

# CLI Overview

Fontisan includes a comprehensive command-line interface.

## Available Commands

| Command | Description |
|---------|-------------|
| `convert` | Convert between font formats |
| `info` | Get font information |
| `validate` | Validate fonts |
| `subset` | Subset fonts |
| `pack` | Create font collections |
| `unpack` | Extract from collections |
| `export` | Export to TTX, SVG, etc. |
| `ls` | List fonts in collection |
| `instance` | Generate variable font instances |

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

# Command help
fontisan convert --help
fontisan validate --help
```

## Output Formats

### Text (default)

```bash
fontisan info font.ttf
```

### YAML

```bash
fontisan info font.ttf --format yaml
```

### JSON

```bash
fontisan info font.ttf --format json
```

## Guides

- [convert](/guide/cli/convert) — Format conversion
- [info](/guide/cli/info) — Font information
- [validate](/guide/cli/validate) — Validation
- [subset](/guide/cli/subset) — Subsetting
- [pack](/guide/cli/pack) — Collections

## Examples

### Basic Conversion

```bash
fontisan convert input.ttf --to otf --output output.otf
```

### Validate for Web

```bash
fontisan validate font.ttf --profile web
```

### Extract Collection

```bash
fontisan unpack fonts.ttc --output-dir ./extracted
```

### Generate Instance

```bash
fontisan instance variable.ttf --wght 700 --output bold.ttf
```
