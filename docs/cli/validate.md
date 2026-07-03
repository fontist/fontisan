---
title: validate
---

# validate

Validate fonts against industry-standard profiles.

## Quick Reference

```bash
fontisan validate <font> --profile <profile> [options]
```

## Validation Profiles

| Profile | Description |
|---------|-------------|
| `opentype` | OpenType specification compliance |
| `google_fonts` | Google Fonts requirements |
| `microsoft` | Microsoft font standards |
| `adobe` | Adobe font guidelines |
| `production` | Production-ready validation |

## Options

| Option | Description |
|--------|-------------|
| `--profile NAME` | Validation profile to use |
| `--format FORMAT` | Output format (text, yaml, json) |
| `--verbose` | Show all checks and results |

## Examples

```bash
# Validate for Google Fonts
fontisan validate font.ttf --profile google_fonts

# Validate for production
fontisan validate font.ttf --profile production

# JSON output
fontisan validate font.ttf --profile opentype --format json
```

## Detailed Documentation

For comprehensive documentation including profile details and validation helpers, see the [validate command guide](/guide/cli/validate).

## See also

For collection-level structural checks (face count, per-face glyph cap,
cmap-union size) on a TTC/OTC/dfont, see
[validate-collection](/cli/validate-collection). The two commands are
complementary: `validate` runs profile-based per-face checks;
`validate-collection` runs collection-level structural checks.
