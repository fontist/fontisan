---
title: Migrate from otfinfo
---

# Migrate from otfinfo

This guide helps you migrate from otfinfo (lcdf-typetools) to Fontisan.

## Overview

otfinfo is part of the lcdf-typetools suite. Fontisan provides equivalent functionality with additional features.

## Command Equivalents

### Font Information

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -i font.ttf` | `fontisan info font.ttf` |
| `otfinfo --info font.ttf` | `fontisan info font.ttf` |

### Script Information

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -s font.ttf` | `fontisan info font.ttf --features` |
| `otfinfo --scripts font.ttf` | `fontisan info font.ttf --features` |

### Feature Information

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -f font.ttf` | `fontisan info font.ttf --features` |
| `otfinfo --features font.ttf` | `fontisan info font.ttf --features` |

### Glyph Information

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -g font.ttf` | `fontisan info font.ttf --glyphs` |
| `otfinfo --glyphs font.ttf` | `fontisan info font.ttf --glyphs` |

### Unicode Coverage

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -u font.ttf` | `fontisan info font.ttf --unicode` |
| `otfinfo --unicode font.ttf` | `fontisan info font.ttf --unicode` |

### Table Information

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -t font.ttf` | `fontisan info font.ttf --tables` |
| `otfinfo --tables font.ttf` | `fontisan info font.ttf --tables` |

## Output Comparison

### Font Information

**otfinfo:**
```
Family:              Example
Subfamily:           Regular
Full name:           Example Regular
PostScript name:     Example-Regular
Version:             1.000
```

**Fontisan:**
```
Font: font.ttf
Format: TrueType
Family: Example
Style: Regular
PostScript: Example-Regular
Version: 1.000
Glyphs: 268
Tables: 14
```

### Unicode Coverage

**otfinfo:**
```
U+0020..U+007E Basic Latin
U+00A0..U+00FF Latin-1 Supplement
```

**Fontisan:**
```
Unicode Coverage:
  Basic Latin (U+0020-U+007E)
  Latin-1 Supplement (U+00A0-U+00FF)
```

## Additional Features

Fontisan provides features not available in otfinfo:

### Validation

```bash
# Not available in otfinfo
fontisan validate font.ttf --profile production
```

### Conversion

```bash
# Not available in otfinfo
fontisan convert font.ttf --to otf --output font.otf
```

### Subsetting

```bash
# Not available in otfinfo
fontisan subset font.ttf --chars "ABC" --output subset.ttf
```

### Collection Support

```bash
# Limited in otfinfo
fontisan ls family.ttc
fontisan unpack family.ttc --output-dir ./extracted
```

### Multiple Output Formats

```bash
# otfinfo: text only
# Fontisan: text, YAML, JSON

fontisan info font.ttf --format yaml
fontisan info font.ttf --format json
```

## Feature Comparison

| Feature | otfinfo | Fontisan |
|---------|---------|----------|
| Font info | ✅ | ✅ |
| Script info | ✅ | ✅ |
| Feature info | ✅ | ✅ |
| Glyph info | ✅ | ✅ |
| Unicode info | ✅ | ✅ |
| Table info | ✅ | ✅ |
| Validation | ❌ | ✅ |
| Conversion | ❌ | ✅ |
| Subsetting | ❌ | ✅ |
| Collections | Limited | ✅ |
| YAML/JSON | ❌ | ✅ |
| Pure Ruby | ❌ (C++) | ✅ |

## Migration Example

### Before (otfinfo)

```bash
# Get family name
family=$(otfinfo -i font.ttf | grep Family | cut -d: -f2 | xargs)
echo "Family: $family"

# Check for specific feature
if otfinfo -f font.ttf | grep -q "liga"; then
  echo "Has ligatures"
fi
```

### After (Fontisan)

```bash
# Get family name (JSON output)
family=$(fontisan info font.ttf --format json | jq -r '.family')
echo "Family: $family"

# Check for specific feature
if fontisan info font.ttf --features | grep -q "liga"; then
  echo "Has ligatures"
fi
```

## Advantages of Fontisan

1. **Pure Ruby** — No C++ compilation required
2. **More features** — Validation, conversion, subsetting
3. **Better output** — YAML and JSON formats
4. **Collection support** — Full TTC/OTC handling
5. **Validation** — Comprehensive font checking

## Getting Help

- [Fontisan Guide](/guide/)
- [CLI Reference](/guide/cli/)
- [GitHub Issues](https://github.com/fontist/fontisan/issues)
