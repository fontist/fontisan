# Fontisan Documentation Summary

This document provides an overview of all Fontisan documentation files and their purpose.

## Main Documentation

### README.adoc
Primary user guide and reference documentation for Fontisan.

## Feature Guides

### Font Hinting
- **File**: `docs/FONT_HINTING.adoc`
- **Purpose**: Documentation for font hinting features in Fontisan
- **Topics**: TrueType and PostScript hinting, hint extraction and application

### Variable Font Operations
- **File**: `docs/VARIABLE_FONT_OPERATIONS.adoc`
- **Purpose**: Guide for working with variable fonts
- **Topics**: Instance generation, axis manipulation, variation preservation

### TTC Migration Guide
- **File**: `docs/EXTRACT_TTC_MIGRATION.md`
- **Purpose**: Migration guide for users of the `extract-ttc` gem
- **Topics**: Moving from extract-ttc to Fontisan pack/unpack commands

### Web Font Formats
- **File**: `docs/WOFF_WOFF2_FORMATS.adoc`
- **Purpose**: Documentation for WOFF and WOFF2 web font formats
- **Topics**: Conversion to/from WOFF/WOFF2, web optimization

### Color Fonts
- **File**: `docs/COLOR_FONTS.adoc`
- **Purpose**: Guide for color font formats
- **Topics**: COLR/CPAL, SVG-in-OpenType, sbix color fonts

### Validation
- **File**: `docs/VALIDATION.adoc`
- **Purpose**: Font validation framework documentation
- **Topics**: Validation profiles, quality checks, OpenType spec compliance

### Apple Legacy Fonts
- **File**: `docs/APPLE_LEGACY_FONTS.adoc`
- **Purpose**: Documentation for Apple legacy font formats
- **Topics**: dfont format, Mac suitcase fonts

### Collection Validation
- **File**: `docs/COLLECTION_VALIDATION.adoc`
- **Purpose**: Guide for validating font collections (TTC/OTC/dfont)
- **Topics**: Collection-specific validation, profile selection

## CLI Commands Reference

Fontisan provides the following CLI commands:

| Command | Purpose |
|---------|---------|
| `info` | Display font information |
| `ls` | List contents (fonts in collection or font summary) |
| `tables` | List OpenType tables |
| `glyphs` | List glyph names |
| `unicode` | List Unicode to glyph mappings |
| `variable` | Display variable font information |
| `optical-size` | Display optical size information |
| `scripts` | List supported scripts from GSUB/GPOS tables |
| `features` | List GSUB/GPOS features |
| `subset` | Subset a font to specific glyphs |
| `convert` | Convert font to different format |
| `instance` | Generate static font instance from variable font |
| `pack` | Pack multiple fonts into TTC/OTC collection |
| `unpack` | Unpack fonts from TTC/OTC collection |
| `validate` | Validate font file |
| `export` | Export font to TTX/YAML/JSON format |
| `dump-table` | Dump raw table data to stdout |
| `version` | Display version information |

## Ruby API Reference

### Fontisan Module Methods

#### `Fontisan.info(path, brief: false, font_index: 0)`
Get font information. Supports both full and brief modes.

- **Parameters**:
  - `path` (String): Path to font file
  - `brief` (Boolean): Use brief mode for fast identification (default: false)
  - `font_index` (Integer): Index for TTC/OTC files (default: 0)
- **Returns**: `Models::FontInfo`, `Models::CollectionInfo`, or `Models::CollectionBriefInfo`
- **Example**:
  ```ruby
  info = Fontisan.info("font.ttf", brief: true)
  puts info.family_name
  ```

#### `Fontisan.validate(path, profile: :default, options: {})`
Validate a font file using specified profile.

- **Parameters**:
  - `path` (String): Path to font file
  - `profile` (Symbol/String): Validation profile (default: :default)
  - `options` (Hash): Additional validation options
- **Available Profiles**:
  - `:indexability` - Fast validation for font discovery
  - `:usability` - Basic usability for installation
  - `:production` - Comprehensive quality checks (default)
  - `:web` - Web embedding and optimization
  - `:spec_compliance` - Full OpenType spec compliance
  - `:default` - Alias for production profile
- **Returns**: `Models::ValidationReport`
- **Example**:
  ```ruby
  report = Fontisan.validate("font.ttf", profile: :web)
  puts "Errors: #{report.summary.errors}"
  ```

### Fontisan::FontLoader

Module for loading fonts in different modes.

- **Methods**:
  - `load(path, mode: :full)` - Load a font file
- **Loading Modes**:
  - `:full` - Load all tables
  - `:metadata` - Load only metadata tables (name, head, hhea, maxp, OS/2, post)
  - `:tables` - Load specific tables only
  - `:structure` - Load structure tables only

## Verification

Documentation examples are verified by `spec/documentation_examples_spec.rb`.

This spec ensures that:
1. All CLI commands referenced in documentation exist
2. All Ruby API methods are available
3. All documentation files are present
4. Command examples reference valid commands

Run verification with:
```bash
bundle exec rspec spec/documentation_examples_spec.rb -v
```
