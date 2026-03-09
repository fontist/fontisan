---
title: vs fonttools
---

# Fontisan vs fonttools

Compare Fontisan with Python's fonttools library.

## Overview

| | fonttools | Fontisan |
|---|-----------|----------|
| Language | Python | Ruby |
| Dependencies | Python + extensions | Pure Ruby |
| Native code | Required | None |
| Validation | External tools | Built-in |

## Feature Comparison

### Font Formats

| Format | fonttools | Fontisan |
|--------|-----------|----------|
| TrueType (TTF) | ✅ | ✅ |
| OpenType (OTF) | ✅ | ✅ |
| WOFF | ✅ | ✅ |
| WOFF2 | ✅ | ✅ |
| Type 1 (PFB/PFA) | Partial | ✅ |
| TTC/OTC | ✅ | ✅ |
| dfont | ✅ | ✅ |
| SVG | ✅ | ✅ |
| UFO | ✅ | Planned |

### Font Operations

| Operation | fonttools | Fontisan |
|-----------|-----------|----------|
| Font loading | ✅ | ✅ |
| Font saving | ✅ | ✅ |
| Table access | ✅ | ✅ |
| TTX export | ✅ | ✅ |
| Subsetting | ✅ | ✅ |
| Merging | ✅ | ✅ |

### Variable Fonts

| Feature | fonttools | Fontisan |
|---------|-----------|----------|
| fvar reading | ✅ | ✅ |
| gvar reading | ✅ | ✅ |
| CFF2 reading | ✅ | ✅ |
| Instance generation | ✅ | ✅ |
| Format conversion | ✅ | ✅ |

### Font Conversion

| Conversion | fonttools | Fontisan |
|------------|-----------|----------|
| TTF ↔ OTF | ✅ | ✅ |
| TTF ↔ WOFF | ✅ | ✅ |
| TTF ↔ WOFF2 | ✅ | ✅ |
| Type 1 → OTF | ✅ | ✅ |
| OTF → Type 1 | ❌ | ✅ |
| Curve conversion | ✅ | ✅ |

### Hinting

| Feature | fonttools | Fontisan |
|---------|-----------|----------|
| TrueType instructions | Read | Read |
| PostScript hints | Read | Read |
| Hint conversion | ❌ | ✅ |
| Bidirectional | ❌ | ✅ |
| Autohint | External | ✅ |

### Validation

| Feature | fonttools | Fontisan |
|---------|-----------|----------|
| Built-in validation | ❌ | ✅ |
| Validation profiles | ❌ | ✅ (5) |
| Validation helpers | ❌ | ✅ (56) |
| Custom validators | ❌ | ✅ |
| Coverage reports | ❌ | ✅ |

### Collections

| Feature | fonttools | Fontisan |
|---------|-----------|----------|
| TTC/OTC reading | ✅ | ✅ |
| TTC/OTC writing | ✅ | ✅ |
| Table deduplication | ✅ | ✅ |
| dfont support | ✅ | ✅ |

## Unique Features

### Fontisan Unique

- **Pure Ruby** — No Python, no native extensions
- **Built-in validation** — 5 profiles, 56 helpers
- **Bidirectional hint conversion** — TrueType ↔ PostScript
- **Custom validators** — DSL for validation rules
- **Type 1 roundtrip** — Full conversion support

### fonttools Unique

- **UFO format** — Full UFO 3 support
- **FEA parsing** — Adobe Feature Expressions
- **Designspace** — MutatorMath integration
- **Extensive ecosystem** — Many third-party tools

## Performance

### Installation

| Metric | fonttools | Fontisan |
|--------|-----------|----------|
| Python required | Yes | No |
| C extensions | Often required | No |
| Install time | 30-60s | 5-10s |
| Dependencies | Many | None |

### Runtime

Both libraries are fast enough for most use cases. Fontisan's pure Ruby approach has minimal overhead for typical operations.

## Use Case Recommendations

### Use Fontisan When:

- You're in a Ruby environment
- You need validation built-in
- You need hint conversion
- You want minimal dependencies
- You're deploying to constrained environments

### Use fonttools When:

- You're in a Python environment
- You need UFO/FEA support
- You need Designspace support
- You rely on the Python font ecosystem

## Code Comparison

### Load and Save

```python
# fonttools
from fontTools.ttLib import TTFont
font = TTFont('input.ttf')
font.save('output.ttf')
```

```ruby
# Fontisan
font = Fontisan::FontLoader.load('input.ttf')
Fontisan::FontWriter.write(font, 'output.ttf')
```

### Access Table

```python
# fonttools
name = font['name'].getBestFamilyName()
```

```ruby
# Fontisan
name = font.tables['name'].family_name
```

### Variable Font Instance

```python
# fonttools
from fontTools.varLib.instancer import instantiateVariableFont
instance = instantiateVariableFont(font, {'wght': 700})
```

```ruby
# Fontisan
writer = Fontisan::Variation::InstanceWriter.new(font)
instance = writer.generate_instance(wght: 700)
```

## Migration

See [Migrate from fonttools](/guide/migrations/fonttools) for a detailed migration guide.

## Conclusion

| Need | Recommendation |
|------|----------------|
| Ruby environment | Fontisan |
| Python environment | fonttools |
| Validation | Fontisan |
| UFO/FEA | fonttools |
| Hint conversion | Fontisan |
| Minimal dependencies | Fontisan |
