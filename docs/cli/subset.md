---
title: subset
---

# subset

Create font subsets with reduced character sets.

## Quick Reference

```bash
fontisan subset <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--chars TEXT` | Characters to include |
| `--file FILE` | File containing characters |
| `--output FILE` | Output file path |
| `--format FORMAT` | Output format |

## Examples

```bash
# Subset to specific characters
fontisan subset font.ttf --chars "ABCDEF" --output subset.ttf

# Subset from file
fontisan subset font.ttf --file chars.txt --output subset.ttf

# Subset and convert format
fontisan subset font.ttf --chars "Hello" --format woff2
```

## Detailed Documentation

For comprehensive documentation including unicode ranges and advanced subsetting, see the [subset command guide](/guide/cli/subset).
