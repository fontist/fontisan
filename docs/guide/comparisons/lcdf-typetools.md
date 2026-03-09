---
title: vs lcdf-typetools
---

# Fontisan vs lcdf-typetools

Compare Fontisan with the lcdf-typetools suite (otfinfo, cfftot1, t1dotlessj, etc.).

## Overview

lcdf-typetools is a C++ suite including:
- `otfinfo` — Font information
- `cfftot1` — CFF to Type 1 conversion
- `t1dotlessj` — Type 1 manipulation
- `t1reencode` — Type 1 reencoding
- `ttf2otf` — TTF to OTF conversion

| | lcdf-typetools | Fontisan |
|---|----------------|----------|
| Language | C++ | Ruby |
| Compilation | Required | None |
| Installation | Complex | `gem install` |
| Cross-platform | Limited | Full |

## Tool Equivalents

### otfinfo

| otfinfo | Fontisan |
|---------|----------|
| `otfinfo -i font.ttf` | `fontisan info font.ttf` |
| `otfinfo -s font.ttf` | `fontisan info font.ttf --features` |
| `otfinfo -f font.ttf` | `fontisan info font.ttf --features` |
| `otfinfo -g font.ttf` | `fontisan info font.ttf --glyphs` |
| `otfinfo -u font.ttf` | `fontisan info font.ttf --unicode` |
| `otfinfo -t font.ttf` | `fontisan info font.ttf --tables` |

### cfftot1

| cfftot1 | Fontisan |
|---------|----------|
| `cfftot1 font.otf` | `fontisan convert font.otf --to type1 --output font.pfb` |

### t1reencode

| t1reencode | Fontisan |
|------------|----------|
| `t1reencode font.pfb` | `fontisan convert font.pfb --to type1 --auto-encoding` |

### ttf2otf

| ttf2otf | Fontisan |
|---------|----------|
| `ttf2otf font.ttf` | `fontisan convert font.ttf --to otf --output font.otf` |

## Feature Comparison

### Font Information

| Feature | otfinfo | Fontisan |
|---------|---------|----------|
| Basic info | ✅ | ✅ |
| Script info | ✅ | ✅ |
| Feature info | ✅ | ✅ |
| Glyph info | ✅ | ✅ |
| Unicode info | ✅ | ✅ |
| Table info | ✅ | ✅ |
| YAML/JSON | ❌ | ✅ |

### Font Conversion

| Feature | lcdf-typetools | Fontisan |
|---------|----------------|----------|
| TTF → OTF | ✅ (ttf2otf) | ✅ |
| OTF → TTF | ❌ | ✅ |
| OTF → Type 1 | ✅ (cfftot1) | ✅ |
| Type 1 → OTF | ❌ | ✅ |
| TTF → WOFF2 | ❌ | ✅ |

### Hinting

| Feature | lcdf-typetools | Fontisan |
|---------|----------------|----------|
| TrueType hints | Read | Read |
| PostScript hints | Read | Read |
| Hint conversion | Partial | ✅ |
| Bidirectional | ❌ | ✅ |

### Validation

| Feature | lcdf-typetools | Fontisan |
|---------|----------------|----------|
| Validation | ❌ | ✅ |
| Profiles | ❌ | ✅ (5) |
| Helpers | ❌ | ✅ (56) |

### Collections

| Feature | lcdf-typetools | Fontisan |
|---------|----------------|----------|
| TTC/OTC reading | ❌ | ✅ |
| TTC/OTC writing | ❌ | ✅ |
| dfont support | ❌ | ✅ |

## Unique Features

### Fontisan Unique

- **Pure Ruby** — No C++ compilation
- **Built-in validation** — Comprehensive checking
- **Bidirectional hint conversion** — TrueType ↔ PostScript
- **Full collection support** — TTC/OTC/dfont
- **Type 1 → OTF** — Reverse conversion
- **WOFF/WOFF2** — Web font support

### lcdf-typetools Unique

- **t1dotlessj** — Specialized Type 1 manipulation
- **t1lint** — Type 1 linting
- **Fast C++** — Native performance
- **Mature** — Long history

## Installation Comparison

### lcdf-typetools

```bash
# macOS
brew install lcdf-typetools

# Linux
apt install lcdf-typetools
# or compile from source

# Windows
# Requires MSYS2 or WSL
```

### Fontisan

```bash
# All platforms
gem install fontisan
```

## Use Case Recommendations

### Use Fontisan When:

- You need validation
- You need WOFF/WOFF2
- You need collection support
- You want minimal installation
- You need Type 1 → OTF conversion

### Use lcdf-typetools When:

- You need t1dotlessj
- You need t1lint
- You're in a C++ environment
- You have existing workflows

## Code Comparison

### Get Font Info

```bash
# otfinfo
otfinfo -i font.ttf | grep Family

# Fontisan
fontisan info font.ttf --format json | jq '.family'
```

### Convert TTF to OTF

```bash
# ttf2otf
ttf2otf font.ttf font.otf

# Fontisan
fontisan convert font.ttf --to otf --output font.otf
```

### Convert OTF to Type 1

```bash
# cfftot1
cfftot1 font.otf font.pfb

# Fontisan
fontisan convert font.otf --to type1 --output font.pfb
```

## Conclusion

| Need | Recommendation |
|------|----------------|
| Ruby environment | Fontisan |
| Validation | Fontisan |
| WOFF/WOFF2 | Fontisan |
| Collections | Fontisan |
| t1dotlessj | lcdf-typetools |
| Type 1 linting | lcdf-typetools |
| Minimal installation | Fontisan |
