---
title: Validation Helpers
---

# Validation Helpers

Fontisan includes 56 validation helpers organized into categories.

## Table Validation

### required_tables

Checks for required OpenType tables.

```ruby
# Required: name, head, maxp, hhea, post
# Optional but common: cmap, hmtx, loca, glyf/cff
```

### table_checksums

Validates table checksums.

### table_lengths

Verifies table lengths match headers.

## Name Table Validation

### name_version

Validates version string format.

### family_name

Checks family name presence and format.

### postscript_name

Validates PostScript name compliance.

### name_completeness

Verifies all required name records.

### name_encoding

Validates name record encoding.

## Head Table Validation

### head_magic

Validates magic number (0x5F0F3CF5).

### head_version

Checks head table version.

### head_units_per_em

Validates UPM value (typically 1000 or 2048).

### head_timestamps

Checks created/modified timestamps.

## Metrics Validation

### hhea_metrics

Validates horizontal header metrics.

### vhea_metrics

Validates vertical header metrics.

### os2_metrics

Validates OS/2 table metrics.

### line_gap

Checks line gap values.

## Glyph Validation

### glyph_count

Verifies glyph count consistency.

### glyph_bounds

Validates glyph bounding boxes.

### composite_glyphs

Checks composite glyph structure.

### glyph_names

Validates glyph naming.

## CMAP Validation

### cmap_presence

Checks cmap table presence.

### cmap_format

Validates cmap format.

### cmap_coverage

Checks Unicode coverage.

### cmap_duplicates

Detects duplicate mappings.

## Layout Table Validation

### gsub_validity

Validates GSUB table structure.

### gpos_validity

Validates GPOS table structure.

### feature_list

Checks feature list validity.

### script_list

Validates script list.

## Advanced Validation

### hint_validity

Validates TrueType hints.

### cff_validity

Validates CFF table structure.

### glyf_loca_consistency

Checks glyf/loca consistency.

### maxp_accuracy

Verifies maxp values accuracy.

## Using Helpers Programmatically

```ruby
require 'fontisan'

font = Fontisan::FontLoader.load('font.ttf')
validator = Fontisan::Validators::FontValidator.new(font)

# Run specific helper
result = validator.check_required_tables
puts result.valid?  # => true or false

# Get all helper results
results = validator.run_all_helpers
results.each do |check_id, result|
  puts "#{check_id}: #{result.status}"
end
```

## Helper Categories

| Category | Helpers | Focus |
|----------|---------|-------|
| Table | 12 | Table structure |
| Name | 8 | Name records |
| Head | 6 | Header validation |
| Metrics | 10 | Font metrics |
| Glyph | 8 | Glyph data |
| CMAP | 6 | Character mapping |
| Layout | 6 | GSUB/GPOS |
| Advanced | 10 | Complex checks |
