---
title: validate
---

# validate

Validate fonts for correctness.

## Usage

```bash
fontisan validate FONT [options]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `FONT` | Font file to validate |
| `FONT ...` | Multiple files |

## Options

| Option | Description |
|--------|-------------|
| `-t, --profile PROFILE` | Validation profile |
| `-S, --summary` | Show summary only |
| `-T, --table` | Table format output |
| `--list` | List available profiles |

## Profiles

| Profile | Description |
|---------|-------------|
| `indexability` | Fast font discovery |
| `usability` | Installation compatibility |
| `production` | Comprehensive quality (default) |
| `web` | Web embedding readiness |
| `spec_compliance` | Full spec compliance |

## Examples

### Basic Validation

```bash
fontisan validate font.ttf

# Font: font.ttf
# Status: VALID
#
# Summary:
#   Checks performed: 37
#   Passed: 37
#   Failed: 0
```

### With Profile

```bash
fontisan validate font.ttf -t web

# Font: font.ttf
# Profile: web
# Status: INVALID
#
# Summary:
#   Checks performed: 18
#   Passed: 17
#   Failed: 1
#
# Failed checks:
#   web_font_tables - Missing required GSUB table
```

### Summary Only

```bash
fontisan validate font.ttf -S

# font.ttf: VALID (37/37 checks passed)
```

### Table Format

```bash
fontisan validate font.ttf -T

# CHECK_ID            | STATUS | SEVERITY | TABLE
# --------------------------------------------------
# required_tables     | PASS   | error    | N/A
# name_version        | PASS   | error    | name
# family_name         | PASS   | error    | name
# head_magic          | PASS   | error    | head
# ...
```

### Multiple Files

```bash
fontisan validate fonts/*.ttf

# fonts/regular.ttf: VALID
# fonts/bold.ttf: VALID
# fonts/italic.ttf: INVALID (1 error)
```

### List Profiles

```bash
fontisan validate --list

# Available validation profiles:
#   indexability    - Fast validation for font discovery
#   usability       - Basic usability for installation
#   production      - Comprehensive quality checks
#   web             - Web embedding and optimization
#   spec_compliance - Full OpenType spec compliance
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Valid |
| 1 | Invalid (errors found) |
| 2 | Error (file not found, etc.) |

## Use in Scripts

```bash
# Validate before release
fontisan validate font.ttf -t production
if [ $? -eq 0 ]; then
  echo "Ready for release"
else
  echo "Validation failed"
  exit 1
fi
```
