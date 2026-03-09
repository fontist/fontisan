---
title: Font Formats Overview
---

# Font Formats Overview

Fontisan supports a wide range of font formats.

## Supported Formats

### Modern Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| TrueType | .ttf | Standard TrueType font |
| OpenType | .otf | CFF-based OpenType font |
| WOFF | .woff | Web Open Font Format |
| WOFF2 | .woff2 | Web Open Font Format 2 |

### Legacy Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| Type 1 | .pfb, .pfa | Adobe Type 1 font |
| dfont | .dfont | Apple Data Fork font |
| TTC | .ttc | TrueType Collection |
| OTC | .otc | OpenType Collection |

### Other Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| SVG | .svg | SVG font |

## Guides

- [TrueType (TTF)](/guide/formats/ttf) — TrueType font format
- [OpenType (OTF)](/guide/formats/otf) — OpenType/CFF format
- [Type 1 (PFB/PFA)](/guide/formats/type1) — Adobe Type 1 fonts
- [WOFF & WOFF2](/guide/formats/woff) — Web font formats
- [Collections](/guide/formats/collections) — TTC and OTC collections
- [Apple dfont](/guide/formats/dfont) — Apple legacy format
- [SVG Fonts](/guide/formats/svg) — SVG-based fonts

## Format Detection

Fontisan automatically detects font format:

```ruby
# Works with any format
font = Fontisan::FontLoader.load('font.ttf')
font = Fontisan::FontLoader.load('font.otf')
font = Fontisan::FontLoader.load('font.pfb')
font = Fontisan::FontLoader.load('font.woff2')
```

## Conversion Matrix

| From | To TTF | To OTF | To WOFF | To WOFF2 |
|------|--------|--------|---------|----------|
| TTF | ✓ | ✓ | ✓ | ✓ |
| OTF | ✓ | ✓ | ✓ | ✓ |
| Type 1 | ✓ | ✓ | ✓ | ✓ |
| WOFF | ✓ | ✓ | ✓ | ✓ |
| WOFF2 | ✓ | ✓ | ✓ | ✓ |
