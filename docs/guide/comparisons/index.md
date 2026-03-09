---
title: Feature Comparisons
---

# Feature Comparisons

Compare Fontisan's capabilities with other popular font processing tools.

## Comparison Pages

### vs fonttools

[→ Compare with fonttools](/guide/comparisons/fonttools)

Comprehensive comparison with Python's fonttools library:
- Font formats (TTF, OTF, TTC, WOFF, WOFF2, Type 1, SVG, UFO)
- Variable fonts (instancing, conversion, axes)
- Font conversion (TTF↔OTF, curves, hints)
- Font validation
- Color fonts
- Hinting
- Collections

### vs lcdf-typetools

[→ Compare with lcdf-typetools](/guide/comparisons/lcdf-typetools)

Comparison with the lcdf-typetools suite (otfinfo, cfftot1, etc.):
- Font information extraction
- CFF/Type 1 conversion
- Font validation
- Hint handling

### vs Font-Validator

[→ Compare with Font-Validator](/guide/comparisons/font-validator)

Comparison with Microsoft's Font-Validator:
- Validation profiles
- Helper coverage
- Reporting capabilities

## Key Advantages

### 💎 Pure Ruby

Fontisan is 100% pure Ruby with no external dependencies:

- **No Python** required (unlike fonttools)
- **No C++ compilation** needed (unlike lcdf-typetools)
- **No .NET runtime** required (unlike Font-Validator)
- Works anywhere Ruby runs — Linux, macOS, Windows, BSD

### 🔄 Bidirectional Hint Conversion

Fontisan is the **only** library that supports bidirectional hint conversion:

- TrueType instructions → PostScript hints
- PostScript hints → TrueType instructions
- Automatic hint generation (autohint)

### ✅ Built-in Validation

Unlike fonttools, Fontisan includes comprehensive validation:

- 5 validation profiles
- 56 validation helpers
- Custom validation DSL
- Detailed error reporting

### 📦 All-in-One

Fontisan combines capabilities from multiple tools:

| Capability | fonttools | lcdf-typetools | Font-Validator | Fontisan |
|-----------|-----------|----------------|----------------|----------|
| Font conversion | ✅ | ✅ | ❌ | ✅ |
| Font validation | ❌ | ❌ | ✅ | ✅ |
| Variable fonts | ✅ | ❌ | ❌ | ✅ |
| Type 1 support | Partial | ✅ | ❌ | ✅ |
| Color fonts | ✅ | ❌ | ❌ | ✅ |
| Hint conversion | ❌ | Partial | ❌ | ✅ |
| **Pure Ruby** | ❌ | ❌ | ❌ | ✅ |
