---
title: features
---

# features

List OpenType features in a font.

## Quick Reference

```bash
fontisan features <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--script TAG` | Filter by script |
| `--language TAG` | Filter by language |
| `--detail` | Show feature details |

## Output

Shows:
- Feature tags
- Feature names/descriptions
- Scripts that use each feature
- Lookup count

## Examples

```bash
# List all features
fontisan features font.ttf

# Features for specific script
fontisan features font.ttf --script latn

# With details
fontisan features font.ttf --detail

# JSON output
fontisan features font.ttf --format json
```

## Sample Output

```
OpenType Features
=================

Tag     Name                    Scripts    Lookups
------  ----------------------  ---------  -------
liga    Standard Ligatures      latn,cyrl  12
dlig    Discretionary Ligatures latn       4
kern    Kerning                 all        156
mark    Mark Positioning        all        48
mkmk    Mark to Mark            all        24
onum    Oldstyle Figures        latn       1
pnum    Proportional Figures    latn       1
tnum    Tabular Figures         latn       1
zero    Slashed Zero            latn       1

Total: 9 features
```

## Common Feature Tags

### GSUB (Substitution) Features

| Tag | Name | Description |
|-----|------|-------------|
| `liga` | Standard Ligatures | fi, fl, etc. |
| `dlig` | Discretionary Ligatures | Optional ligatures |
| `hlig` | Historical Ligatures | Archaic forms |
| `calt` | Contextual Alternates | Context-based |
| `salt` | Stylistic Alternates | Alternate glyphs |
| `ss01`-`ss20` | Stylistic Sets | Grouped alternates |
| `smcp` | Small Capitals | Lowercase to small caps |
| `c2sc` | Caps to Small Caps | Uppercase to small caps |
| `onum` | Oldstyle Figures | Varying height |
| `lnum` | Lining Figures | Uniform height |
| `pnum` | Proportional Figures | Varying width |
| `tnum` | Tabular Figures | Uniform width |
| `zero` | Slashed Zero | Distinguish 0/O |
| `case` | Case-Sensitive Forms | Uppercase adjustment |

### GPOS (Positioning) Features

| Tag | Name | Description |
|-----|------|-------------|
| `kern` | Kerning | Pair adjustments |
| `mark` | Mark Positioning | Diacritics |
| `mkmk` | Mark to Mark | Stacked diacritics |
| `dist` | Distances | Spacing |
| `abvm` | Above Marks | Positioning above |
| `blwm` | Below Marks | Positioning below |

## Use Cases

### Check for Ligatures

```bash
fontisan features font.ttf | grep liga
```

### Check for Small Caps

```bash
fontisan features font.ttf | grep -E "smcp|c2sc"
```

### Compare Feature Sets

```bash
diff <(fontisan features font1.ttf) <(fontisan features font2.ttf)
```

## Related Commands

- [scripts](/cli/scripts) — List supported scripts
- [info](/cli/info) — Get comprehensive font info
