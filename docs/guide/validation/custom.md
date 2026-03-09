---
title: Custom Validators
---

# Custom Validators

Create custom validation rules using Fontisan's validation DSL.

## Overview

Custom validators inherit from `Fontisan::Validators::Validator` and define validation logic using the DSL.

## DSL Methods

The DSL provides 6 check methods:

| Method | Description |
|--------|-------------|
| `check_table` | Validate table-level properties |
| `check_field` | Validate specific field values |
| `check_structure` | Validate font structure and relationships |
| `check_usability` | Validate usability and best practices |
| `check_instructions` | Validate TrueType instructions/hinting |
| `check_glyphs` | Validate individual glyphs |

## Creating a Validator

### Basic Structure

```ruby
require 'fontisan/validators/validator'

class MyFontValidator < Fontisan::Validators::Validator
  private

  def define_checks
    # Define your checks here
  end
end
```

### Table Validation

```ruby
def define_checks
  # Check name table
  check_table :name_validation, 'name', severity: :error do |table|
    table.valid_version? &&
      table.valid_encoding_heuristics? &&
      table.family_name_present? &&
      table.postscript_name_valid?
  end

  # Check head table
  check_table :head_validation, 'head', severity: :error do |table|
    table.valid_magic? &&
      table.valid_version? &&
      table.valid_units_per_em?
  end
end
```

### Structure Validation

```ruby
def define_checks
  check_structure :required_tables, severity: :error do |font|
    %w[name head maxp hhea].all? { |tag| !font.table(tag).nil? }
  end

  check_structure :optional_tables, severity: :warning do |font|
    # Check for recommended optional tables
    %w[cmap hmtx].all? { |tag| !font.table(tag).nil? }
  end
end
```

### Field Validation

```ruby
def define_checks
  check_field :units_per_em, 'head.units_per_em', severity: :error do |value|
    [1000, 2048].include?(value)
  end

  check_field :font_revision, 'head.font_revision', severity: :warning do |value|
    value > 0 && value < 100
  end
end
```

### Glyph Validation

```ruby
def define_checks
  check_glyphs :glyph_bounds, severity: :warning do |glyph|
    # Check if glyph has valid bounds
    !glyph.bounds.nil? &&
      glyph.bounds.min_x >= -10000 &&
      glyph.bounds.max_x <= 10000
  end
end
```

## Severity Levels

| Severity | Description |
|----------|-------------|
| `:fatal` | Critical error, font unusable |
| `:error` | Error, font may not work correctly |
| `:warning` | Warning, best practice violation |
| `:info` | Informational, no impact |

## Using Custom Validators

```ruby
# Load font
font = Fontisan::FontLoader.load('font.ttf')

# Create validator instance
validator = MyFontValidator.new(font)

# Run validation
report = validator.validate

# Check results
if report.valid?
  puts "Font is valid!"
else
  report.errors.each do |error|
    puts "#{error.check_id}: #{error.message}"
  end
end
```

## Complete Example

```ruby
require 'fontisan/validators/validator'

class WebFontValidator < Fontisan::Validators::Validator
  private

  def define_checks
    # Required tables for web fonts
    check_structure :web_required_tables, severity: :error do |font|
      required = %w[name head maxp hhea cmap hmtx]
      required.all? { |tag| !font.table(tag).nil? }
    end

    # Name records completeness
    check_table :name_completeness, 'name', severity: :error do |table|
      [
        table.family_name_present?,
        table.subfamily_name_present?,
        table.unique_id_present?,
        table.full_name_present?,
        table.version_present?
      ].all?
    end

    # UPM should be power of 2 for web
    check_field :web_units_per_em, 'head.units_per_em', severity: :info do |value|
      [256, 512, 1024, 2048, 4096].include?(value)
    end

    # Check for GSUB (recommended for web)
    check_structure :web_gsub_presence, severity: :info do |font|
      !font.table('GSUB').nil?
    end
  end
end

# Use the validator
font = Fontisan::FontLoader.load('font.ttf')
validator = WebFontValidator.new(font)
report = validator.validate

puts report.to_summary
```

## Integrating with Profiles

Custom validators can be integrated into validation profiles:

```ruby
# Create a custom profile
profile = Fontisan::Validators::ValidationProfile.new(
  name: :my_custom,
  validators: [MyFontValidator]
)

# Use the profile
report = Fontisan.validate('font.ttf', profile: profile)
```
