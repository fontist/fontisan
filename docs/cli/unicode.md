---
title: unicode
---

# unicode

Show Unicode coverage and character mappings.

## Quick Reference

```bash
fontisan unicode <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--ranges` | Show Unicode ranges |
| `--scripts` | Group by script |
| `--missing` | Show missing from range |

## Output

Shows:
- Unicode ranges covered
- Scripts supported
- Character count per range
- Cmap table summary

## Examples

```bash
# Basic Unicode info
fontisan unicode font.ttf

# Show Unicode ranges
fontisan unicode font.ttf --ranges

# Group by script
fontisan unicode font.ttf --scripts

# JSON output
fontisan unicode font.ttf --format json
```

## Sample Output

```
Unicode Coverage
================

Range                            Characters
-------------------------------  ----------
Basic Latin (U+0000-U+007F)     95
Latin-1 Supplement (U+0080-U+00FF)  96
Latin Extended-A (U+0100-U+017F)    128
Latin Extended-B (U+0180-U+024F)    48
Spacing Modifier Letters (U+02B0-U+02FF) 8
Greek and Coptic (U+0370-U+03FF)    72
Cyrillic (U+0400-U+04FF)            66

Total characters: 513
```

## Common Unicode Ranges

| Range | Name | Typical Use |
|-------|------|-------------|
| U+0000-U+007F | Basic Latin | ASCII |
| U+0080-U+00FF | Latin-1 Supplement | Western European |
| U+0100-U+017F | Latin Extended-A | European |
| U+0400-U+04FF | Cyrillic | Russian, etc. |
| U+0590-U+05FF | Hebrew | Hebrew |
| U+0600-U+06FF | Arabic | Arabic |
| U+0900-U+097F | Devanagari | Hindi, etc. |
| U+4E00-U+9FFF | CJK Unified | Chinese/Japanese |
| U+AC00-U+D7AF | Hangul | Korean |

## Use Cases

### Check Script Support

```bash
fontisan unicode font.ttf --scripts | grep -i cyrillic
```

### Find Coverage Gaps

```bash
fontisan unicode font.ttf --missing
```

### Compare Fonts

```bash
fontisan unicode font1.ttf --format json > unicode1.json
fontisan unicode font2.ttf --format json > unicode2.json
diff <(jq . unicode1.json) <(jq . unicode2.json)
```
