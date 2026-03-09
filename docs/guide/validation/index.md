---
title: Validation Overview
---

# Validation Overview

Fontisan provides a comprehensive validation framework for ensuring font quality, structural integrity, and compliance with OpenType specifications.

## Validation Profiles

Fontisan includes predefined validation profiles:

| Profile | Checks | Speed | Use Case |
|---------|--------|-------|----------|
| `indexability` | 8 | Fast | Font discovery and indexing |
| `usability` | 26 | Medium | Font installation compatibility |
| `production` | 37 | Full | Comprehensive quality (default) |
| `web` | 18 | Medium | Web embedding readiness |
| `spec_compliance` | Full | Slow | OpenType specification compliance |

### List Profiles

```bash
fontisan validate --list

# Available validation profiles:
#   indexability         - Fast validation for font discovery
#   usability            - Basic usability for installation
#   production           - Comprehensive quality checks
#   web                  - Web embedding and optimization
#   spec_compliance      - Full OpenType spec compliance
```

## CLI Usage

### Basic Validation

```bash
# Validate with default profile (production)
fontisan validate font.ttf

# Font: font.ttf
# Status: VALID
#
# Summary:
#   Checks performed: 37
#   Passed: 37
#   Failed: 0
```

### With Specific Profile

```bash
# Validate for web use
fontisan validate font.ttf -t web

# Validate for indexing
fontisan validate font.ttf -t indexability
```

### Output Formats

```bash
# Table format
fontisan validate font.ttf -T

# CHECK_ID                    | STATUS | SEVERITY | TABLE
# ------------------------------------------------------------
# required_tables             | PASS   | error    | N/A
# name_version                | PASS   | error    | name
# family_name                 | PASS   | error    | name
```

### With Summary

```bash
fontisan validate font.ttf -t web -S

# Failed checks:
#   web_font_tables      - Missing required GSUB table
```

## Ruby API

### Basic Validation

```ruby
require 'fontisan'

# Validate with default profile
report = Fontisan.validate('font.ttf')
puts report.valid?  # => true or false

# Validate with specific profile
report = Fontisan.validate('font.ttf', profile: :web)

if report.valid?
  puts "Font is valid!"
else
  puts "Font has #{report.summary.errors} errors"
end
```

### Query Results

```ruby
report = Fontisan.validate('font.ttf', profile: :production)

# Get issues by severity
fatal_issues = report.fatal_errors
error_issues = report.errors_only
warning_issues = report.warnings_only
info_issues = report.info_only

# Get issues by category
table_issues = report.issues_by_category('table_validation')

# Get statistics
failed_ids = report.failed_check_ids
pass_rate = report.pass_rate

# Export results
yaml_output = report.to_yaml
json_output = report.to_json
summary = report.to_summary  # "2 errors, 3 warnings, 0 info"
```

## Next Steps

- [Validation Profiles](/guide/validation/profiles) — Detailed profile documentation
- [Validation Helpers](/guide/validation/helpers) — Individual validation checks
- [Custom Validators](/guide/validation/custom) — Create custom validation rules
