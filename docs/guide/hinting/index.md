---
title: Font Hinting Overview
---

# Font Hinting Overview

Fontisan provides comprehensive support for font hints, including extraction, conversion, validation, and preservation. Hints are rendering instructions embedded in fonts that improve appearance at small sizes and low resolutions.

## Hinting Systems

Fontisan supports two hinting systems:

| System | Format | Storage | Type |
|--------|--------|---------|------|
| TrueType | TTF | prep, fpgm, cvt tables | Bytecode instructions |
| PostScript | OTF | CFF Private DICT | Declarative hints |

### TrueType Instructions

Bytecode-based hints using instruction opcodes:

- `SSW` — Set Single Width
- `SCVTCI` — Set CVT Cut-In
- `WCVTP` — Write CVT in Pixels
- And many more...

Stored in:
- `prep` — Control Value Program
- `fpgm` — Font Program
- `cvt` — Control Value Table

### PostScript Hints

Declarative hints using operators:

- `hstem` — Horizontal stem hints
- `vstem` — Vertical stem hints
- `hintmask` — Hint activation mask

Stored in CFF Private dictionaries.

## Features

- **Bidirectional Conversion** — Convert hints between TrueType and PostScript
- **Hint Extraction** — Extract existing hints from TTF and OTF fonts
- **Hint Application** — Apply hints during format conversion
- **Validation** — Comprehensive validation of hint data
- **Round-Trip Preservation** — Maintain hint integrity during conversion cycles

## Guides

- [TrueType Hinting](/guide/hinting/truetype) — TrueType instruction details
- [PostScript Hinting](/guide/hinting/postscript) — CFF hint parameters
- [Hint Conversion](/guide/hinting/conversion) — Bidirectional conversion
- [Autohint](/guide/hinting/autohint) — Automatic hinting

## Quick Start

### Check for Hints

```ruby
font = Fontisan::FontLoader.load('font.ttf')

# Check TrueType hints
if font.tables['prep'] || font.tables['fpgm']
  puts "TrueType hints present"
end

# Check PostScript hints
if cff = font.tables['CFF']
  private_dict = cff.top_dicts.first[:private]
  if private_dict[:blue_values]
    puts "PostScript hints present"
  end
end
```

### Convert with Hints

```bash
# Preserve hints during conversion
fontisan convert font.ttf --to otf --hinting-mode preserve

# Apply autohinting
fontisan convert font.ttf --to otf --autohint --hinting-mode auto
```
