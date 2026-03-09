---
title: scripts
---

# scripts

List scripts and languages supported by a font.

## Quick Reference

```bash
fontisan scripts <font> [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (text, yaml, json) |
| `--with-languages` | Include language systems |
| `--with-features` | Include features per script |

## Output

Shows:
- Script tags (OpenType 4-character codes)
- Script names
- Language systems (optional)
- Feature count per script

## Examples

```bash
# List scripts
fontisan scripts font.ttf

# With language systems
fontisan scripts font.ttf --with-languages

# With features
fontisan scripts font.ttf --with-features

# JSON output
fontisan scripts font.ttf --format json
```

## Sample Output

```
Scripts
=======

Tag     Name                    Languages  Features
------  ----------------------  ---------  --------
DFLT    Default                 1          12
latn    Latin                   27         45
cyrl    Cyrillic                8          32
grek    Greek                   2          28
arab    Arabic                  4          38

Total: 5 scripts, 42 language systems
```

## Common Script Tags

| Tag | Script |
|-----|--------|
| `DFLT` | Default |
| `latn` | Latin |
| `cyrl` | Cyrillic |
| `grek` | Greek |
| `arab` | Arabic |
| `hebr` | Hebrew |
| `deva` | Devanagari |
| `beng` | Bengali |
| `hans` | Simplified Chinese |
| `hant` | Traditional Chinese |
| `jpan` | Japanese |
| `kore` | Korean |
| `thai` | Thai |

## Use Cases

### Check for Script Support

```bash
fontisan scripts font.ttf | grep -i arab
```

### Verify Multi-script Font

```bash
fontisan scripts font.ttf --format json | jq 'length'
```

### Compare Script Coverage

```bash
diff <(fontisan scripts font1.ttf) <(fontisan scripts font2.ttf)
```

## Related Commands

- [features](/cli/features) — List OpenType features
- [unicode](/cli/unicode) — Show Unicode coverage
