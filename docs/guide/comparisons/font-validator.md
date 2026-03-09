---
title: vs Font-Validator
---

# Fontisan vs Font-Validator

Compare Fontisan with Microsoft's Font-Validator.

## Overview

Font-Validator is Microsoft's C# tool for comprehensive font validation.

| | Font-Validator | Fontisan |
|---|----------------|----------|
| Language | C# | Ruby |
| Runtime | .NET required | None |
| Platform | Windows focus | Cross-platform |
| Features | Validation only | Full suite |

## Profile Equivalents

| Font-Validator | Fontisan |
|----------------|----------|
| Auto | `fontisan validate -t indexability` |
| Full | `fontisan validate -t production` |
| Web | `fontisan validate -t web` |
| Custom | `fontisan validate -t spec_compliance` |

## Feature Comparison

### Validation

| Feature | Font-Validator | Fontisan |
|---------|----------------|----------|
| Profiles | 3+ | 5 |
| Helpers | ~50 | 56 |
| Coverage reports | ✅ | ✅ |
| Custom rules | ❌ | ✅ |
| Severity levels | ✅ | ✅ |
| Output formats | XML | YAML, JSON, Text |

### Font Operations

| Feature | Font-Validator | Fontisan |
|---------|----------------|----------|
| Validation | ✅ | ✅ |
| Conversion | ❌ | ✅ |
| Subsetting | ❌ | ✅ |
| Information | Limited | ✅ |
| Collections | Limited | ✅ |

### Format Support

| Format | Font-Validator | Fontisan |
|--------|----------------|----------|
| TrueType | ✅ | ✅ |
| OpenType | ✅ | ✅ |
| WOFF | ✅ | ✅ |
| WOFF2 | ✅ | ✅ |
| Type 1 | ❌ | ✅ |
| TTC/OTC | Limited | ✅ |

### Variable Fonts

| Feature | Font-Validator | Fontisan |
|---------|----------------|----------|
| fvar validation | ✅ | ✅ |
| gvar validation | ✅ | ✅ |
| Instance generation | ❌ | ✅ |
| Format conversion | ❌ | ✅ |

## Validation Profiles

### Fontisan Profiles

| Profile | Checks | Focus |
|---------|--------|-------|
| indexability | 8 | Fast discovery |
| usability | 26 | Installation |
| production | 37 | Full quality |
| web | 18 | Web fonts |
| spec_compliance | Full | Spec audit |

### Font-Validator Profiles

| Profile | Focus |
|---------|-------|
| Auto | Quick check |
| Full | Comprehensive |
| Web | Web fonts |

## Unique Features

### Fontisan Unique

- **Pure Ruby** — No .NET runtime
- **Font conversion** — TTF ↔ OTF ↔ WOFF
- **Subsetting** — Create font subsets
- **Collections** — Full TTC/OTC support
- **Custom validators** — DSL for rules
- **Variable fonts** — Instance generation
- **Type 1 support** — Legacy format

### Font-Validator Unique

- **Microsoft official** — From the source
- **Deep Windows integration** — Windows-specific checks
- **Mature** — Long development history

## Installation Comparison

### Font-Validator

```bash
# Requires .NET runtime
# Windows: Download MSI
# Linux: Requires Mono or .NET Core
# macOS: Requires .NET Core

dotnet tool install --global FontValidator
```

### Fontisan

```bash
# All platforms, no runtime
gem install fontisan
```

## Use Case Recommendations

### Use Fontisan When:

- You're not on Windows
- You need conversion features
- You need subsetting
- You want custom validators
- You need Type 1 support

### Use Font-Validator When:

- You need Microsoft official validation
- You need Windows-specific checks
- You're in a .NET environment

## Code Comparison

### Basic Validation

```bash
# Font-Validator
FontValidator.exe font.ttf

# Fontisan
fontisan validate font.ttf
```

### With Profile

```bash
# Font-Validator
FontValidator.exe -Profile Full font.ttf

# Fontisan
fontisan validate font.ttf -t production
```

### Output Format

```bash
# Font-Validator
FontValidator.exe -Output report.xml font.ttf

# Fontisan
fontisan validate font.ttf --format json
```

## Custom Validators

Fontisan allows custom validation rules (not available in Font-Validator):

```ruby
class MyValidator < Fontisan::Validators::Validator
  def define_checks
    check_table :name_check, 'name', severity: :error do |table|
      table.family_name_present? &&
        table.postscript_name_valid?
    end
  end
end
```

## CI/CD Integration

### Font-Validator

```yaml
# Requires .NET runtime
- uses: actions/setup-dotnet@v3
- run: FontValidator.exe fonts/*.ttf
```

### Fontisan

```yaml
# Uses Ruby (already available on most runners)
- uses: ruby/setup-ruby@v1
- run: gem install fontisan
- run: fontisan validate fonts/*.ttf
```

## Conclusion

| Need | Recommendation |
|------|----------------|
| Ruby environment | Fontisan |
| Cross-platform | Fontisan |
| Conversion features | Fontisan |
| Custom validation | Fontisan |
| Microsoft official | Font-Validator |
| Windows-specific | Font-Validator |
| .NET environment | Font-Validator |
