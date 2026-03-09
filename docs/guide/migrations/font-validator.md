---
title: Migrate from Font-Validator
---

# Migrate from Font-Validator

This guide helps you migrate from Microsoft's Font-Validator (C#) to Fontisan.

## Overview

Font-Validator is Microsoft's C# tool for font validation. Fontisan provides equivalent validation with additional features, all in pure Ruby.

## Profile Equivalents

| Font-Validator | Fontisan |
|----------------|----------|
| Auto mode | `fontisan validate -t indexability` |
| Full mode | `fontisan validate -t production` |
| Web mode | `fontisan validate -t web` |
| Custom | `fontisan validate -t spec_compliance` |

## Validation Profiles

### indexability (Fast)

Equivalent to Font-Validator Auto mode:

```bash
fontisan validate font.ttf -t indexability

# Fast validation for font discovery
# 8 checks, metadata-only
```

### production (Full)

Equivalent to Font-Validator Full mode:

```bash
fontisan validate font.ttf -t production

# Comprehensive quality checks
# 37 checks, OpenType spec compliance
# This is the default profile
```

### web

Equivalent to Font-Validator Web mode:

```bash
fontisan validate font.ttf -t web

# Web embedding readiness
# 18 checks for web deployment
```

## Command Equivalents

### Basic Validation

**Font-Validator:**
```bash
FontValidator.exe font.ttf
```

**Fontisan:**
```bash
fontisan validate font.ttf
```

### With Profile

**Font-Validator:**
```bash
FontValidator.exe -Profile Auto font.ttf
FontValidator.exe -Profile Full font.ttf
FontValidator.exe -Profile Web font.ttf
```

**Fontisan:**
```bash
fontisan validate font.ttf -t indexability
fontisan validate font.ttf -t production
fontisan validate font.ttf -t web
```

### Output Format

**Font-Validator:**
```bash
FontValidator.exe -Output report.xml font.ttf
```

**Fontisan:**
```bash
fontisan validate font.ttf --format yaml
fontisan validate font.ttf --format json
```

## Output Comparison

### Font-Validator Output

```
=== Font Validation Report ===
File: font.ttf
Overall: PASS

Checks: 50
Passed: 50
Failed: 0
```

### Fontisan Output

```
Font: font.ttf
Status: VALID

Summary:
  Checks performed: 37
  Passed: 37
  Failed: 0

Errors: 0
Warnings: 0
```

## Validation Helpers

Fontisan includes 56 validation helpers:

| Category | Helpers |
|----------|---------|
| Table | 12 |
| Name | 8 |
| Head | 6 |
| Metrics | 10 |
| Glyph | 8 |
| CMAP | 6 |
| Layout | 6 |

See [Validation Helpers](/guide/validation/helpers) for details.

## Additional Features

Fontisan provides features not available in Font-Validator:

### Font Conversion

```bash
# Not available in Font-Validator
fontisan convert font.ttf --to otf --output font.otf
fontisan convert font.ttf --to woff2 --output font.woff2
```

### Font Subsetting

```bash
# Not available in Font-Validator
fontisan subset font.ttf --chars "ABC" --output subset.ttf
```

### Collection Support

```bash
# Limited in Font-Validator
fontisan ls family.ttc
fontisan unpack family.ttc --output-dir ./extracted
```

### Variable Font Support

```bash
# Limited in Font-Validator
fontisan info variable.ttf
fontisan instance variable.ttf --wght 700 --output bold.ttf
```

## Feature Comparison

| Feature | Font-Validator | Fontisan |
|---------|----------------|----------|
| Pure Ruby | ❌ (C#) | ✅ |
| .NET required | ✅ | ❌ |
| Validation | ✅ | ✅ |
| Conversion | ❌ | ✅ |
| Subsetting | ❌ | ✅ |
| Collections | Limited | ✅ |
| Variable fonts | Limited | ✅ |
| Type 1 support | ❌ | ✅ |
| Custom validators | ❌ | ✅ |

## Migration Example

### CI/CD Pipeline

**Before (Font-Validator):**
```yaml
# Requires .NET runtime
- run: FontValidator.exe -Profile Full fonts/*.ttf
```

**After (Fontisan):**
```yaml
# Pure Ruby, no runtime dependencies
- run: fontisan validate fonts/*.ttf -t production
```

### Script

**Before:**
```bash
# Windows only
FontValidator.exe -Profile Full font.ttf
if %ERRORLEVEL% neq 0 (
  echo Validation failed
)
```

**After:**
```bash
# Cross-platform
fontisan validate font.ttf
if [ $? -ne 0 ]; then
  echo "Validation failed"
fi
```

## Custom Validators

Fontisan allows custom validation rules:

```ruby
class MyValidator < Fontisan::Validators::Validator
  def define_checks
    check_table :custom_check, 'name', severity: :error do |table|
      table.family_name_present?
    end
  end
end
```

See [Custom Validators](/guide/validation/custom) for details.

## Advantages of Fontisan

1. **Pure Ruby** — No .NET runtime required
2. **Cross-platform** — Works on Linux, macOS, Windows
3. **More features** — Conversion, subsetting, collections
4. **Custom validators** — Extensible validation
5. **Variable fonts** — Full support
6. **Type 1** — Legacy format support

## Getting Help

- [Validation Guide](/guide/validation/)
- [CLI Reference](/guide/cli/validate)
- [GitHub Issues](https://github.com/fontist/fontisan/issues)
