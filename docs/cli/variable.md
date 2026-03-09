---
title: variable
---

# variable

Inspect variable font axes and named instances.

## Quick Reference

```bash
fontisan variable <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--instances` | Show named instances |
| `--axes` | Show axes only |

## Output

Shows:
- Variation axes with ranges and defaults
- Named instances (presets)
- Axis flags (hidden, etc.)

## Examples

```bash
# Full variable font info
fontisan variable VariableFont.ttf

# Show only axes
fontisan variable VariableFont.ttf --axes

# Show named instances
fontisan variable VariableFont.ttf --instances

# JSON output for processing
fontisan variable VariableFont.ttf --format json
```

## Sample Output

```
Variable Font: VariableFont.ttf
================================

Axes (2)
--------
Tag     Name          Min      Default  Max      Flags
------  -----------   -----    -------  -----    -----
wght    Weight        100      400      900      -
wdth    Width         75%      100%     125%     -

Named Instances (6)
-------------------
Name                  Coordinates
------------------    --------------------
Thin                  wght:100
Light                 wght:300
Regular               wght:400
Medium                wght:500
Bold                  wght:700
Black                 wght:900
```

## Understanding Axes

### Standard Axes

| Tag | Name | Typical Range | Description |
|-----|------|---------------|-------------|
| `wght` | Weight | 1-999 | Font weight (thin to black) |
| `wdth` | Width | 50-200 | Width percentage |
| `slnt` | Slant | -90 to +90 | Slant angle in degrees |
| `ital` | Italic | 0-1 | Italic toggle |
| `opsz` | Optical Size | 8-144 | Point size for optical sizing |

### Registered Axes

| Tag | Name | Description |
|-----|------|-------------|
| `GRAD` | Grade | Weight change without width change |
| `XTRA` | X-tra | X-height adjustment |
| `XOPQ` | X-opaque | Horizontal stroke adjustment |
| `YOPQ` | Y-opaque | Vertical stroke adjustment |
| `YTRA` | Y-tra | Y-height adjustment |
| `YTLC` | Y-lowercase | Lowercase height |
| `YTUC` | Y-uppercase | Uppercase height |
| `YTAS` | Y-ascender | Ascender height |
| `YTDE` | Y-descender | Descender depth |
| `YTFI` | Y-figure | Figure height |

## Use Cases

### Discover Available Instances

```bash
fontisan variable font.ttf --instances
```

### Get Axis Range for Instance Generation

```bash
# Get weight range
fontisan variable font.ttf --format json | jq '.axes[] | select(.tag=="wght")'
```

### Check if Font is Variable

```bash
if fontisan variable font.ttf 2>/dev/null; then
  echo "Variable font"
else
  echo "Static font"
fi
```

## Related Commands

- [instance](/cli/instance) — Generate static instances
- [info](/cli/info) — Get font information
