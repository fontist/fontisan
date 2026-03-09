---
title: instance
---

# instance

Generate static font instances from variable fonts.

::: warning License Consideration
Many commercial variable fonts require a special license to generate static instances. Check your font's EULA before using this command.
:::

## Quick Reference

```bash
fontisan instance <variable-font> [options]
```

## What are Variable Font Instances?

Variable fonts contain multiple variations along design axes (weight, width, slant, etc.). The `instance` command extracts a specific variation as a standalone static font.

For example, a variable font with a `wght` (weight) axis from 100-900 can generate instances like:
- Light (wght: 300)
- Regular (wght: 400)
- Medium (wght: 500)
- Bold (wght: 700)

## Options

| Option | Description |
|--------|-------------|
| `--output FILE` | Output file path |
| `--wght VALUE` | Weight axis value (e.g., 400, 700) |
| `--wdth VALUE` | Width axis value |
| `--slnt VALUE` | Slant axis value |
| `--ital VALUE` | Italic axis value |
| `--opsz VALUE` | Optical size axis value |
| `--named INSTANCE` | Use named instance (e.g., "Bold") |
| `--format FORMAT` | Output format (ttf, otf, woff, woff2) |

## Examples

### Generate by Axis Values

```bash
# Generate Regular weight
fontisan instance VariableFont.ttf --wght 400 --output Regular.ttf

# Generate Bold weight
fontisan instance VariableFont.ttf --wght 700 --output Bold.ttf

# Generate with multiple axes
fontisan instance VariableFont.ttf --wght 500 --wdth 75 --output MediumCondensed.ttf

# Generate with optical size
fontisan instance VariableFont.ttf --wght 400 --opsz 12 --output Text-12pt.ttf
```

### Generate by Named Instance

```bash
# Use a named instance from the font
fontisan instance VariableFont.ttf --named "Bold" --output Bold.ttf

# List available named instances first
fontisan variable VariableFont.ttf
```

### Generate for Web

```bash
# Generate and convert to WOFF2 in one step
fontisan instance VariableFont.ttf --wght 400 --format woff2 --output Regular.woff2
fontisan instance VariableFont.ttf --wght 700 --format woff2 --output Bold.woff2
```

### Batch Generation

```bash
# Generate common weights
for wght in 300 400 500 600 700; do
  fontisan instance VariableFont.ttf --wght $wght --output Font-$wght.ttf
done
```

## Common Axes

| Axis Tag | Name | Typical Range |
|----------|------|---------------|
| `wght` | Weight | 1-999 (100-900 common) |
| `wdth` | Width | 0-200 (% of normal) |
| `slnt` | Slant | -90 to +90 (degrees) |
| `ital` | Italic | 0-1 |
| `opsz` | Optical Size | 8-144 (point size) |
| `GRAD` | Grade | -1 to 1 |
| `XTRA` | X-height | Various |
| `XOPQ` | X opaque | Various |
| `YOPQ` | Y opaque | Various |

## Discovering Axes

Use the `variable` command to see what axes a font has:

```bash
fontisan variable VariableFont.ttf
```

Output shows:
- Available axes with their ranges
- Named instances defined in the font
- Default values

## Detailed Documentation

For comprehensive documentation including:
- How variable fonts work
- Instance generation algorithms
- Handling complex axes
- Format conversion options

See the [Variable Fonts Guide](/guide/variable-fonts/).
