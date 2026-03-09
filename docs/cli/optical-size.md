---
title: optical-size
---

# optical-size

Show optical size information for a font.

## Quick Reference

```bash
fontisan optical-size <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |

## What is Optical Size?

Optical sizing is a typographic technique where glyphs are designed differently for different point sizes. Small sizes need more open shapes and spacing, while large sizes can have more detail and tighter spacing.

Variable fonts can use the `opsz` axis for continuous optical sizing, while static fonts may have separate fonts for different size ranges (Caption, Text, Display, etc.).

## Output

Shows:
- Optical size axis (if variable)
- Size range recommendations
- Design size metadata
- Named instances for sizes

## Examples

```bash
# Show optical size info
fontisan optical-size font.ttf

# JSON output
fontisan optical-size font.ttf --format json
```

## Sample Output

### Variable Font with opsiz Axis

```
Optical Size: VariableFont.ttf
===============================

Axis: opsz (Optical Size)
  Range: 8pt - 144pt
  Default: 12pt

Size Recommendations:
  Caption (6-8pt):    opsz: 8
  Small Text (9-11pt): opsz: 10
  Text (12-14pt):     opsz: 12
  Subhead (14-24pt):  opsz: 18
  Display (24-72pt):  opsz: 48
  Poster (72pt+):     opsz: 72
```

### Static Font with Size Range

```
Optical Size: FontText-Regular.ttf
==================================

Design Size: 12pt (Text)
Size Range: 11-13pt
Style: Text

Recommended for body text usage.
```

## Size Categories

| Category | Point Range | Use Case |
|----------|-------------|----------|
| Caption | 6-8 | Footnotes, captions |
| Small Text | 9-11 | Legal text, fine print |
| Text | 12-14 | Body copy |
| Subhead | 14-24 | Subheadings |
| Title | 24-36 | Headings |
| Display | 36-72 | Large headlines |
| Poster | 72+ | Very large text |

## Related Commands

- [variable](/cli/variable) — Full variable font info
- [info](/cli/info) — General font information
