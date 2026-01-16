# Changelog

All notable changes to Fontisan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive documentation for WOFF/WOFF2 format support
- Color fonts documentation (COLR/CPAL, sbix, SVG tables)
- Font validation framework documentation
- Apple legacy font formats documentation ('true' signature, dfont)
- Font collection validation documentation
- Updated font hinting documentation
- Enhanced README with all v0.2.1-v0.2.7 features

### Changed
- Improved documentation organization with dedicated feature guides
- Added more examples for command-line and Ruby API usage

## [0.2.7] - 2026-01-06

### Added
- Collection validation support with per-font reporting
- CollectionValidationReport model with overall status
- FontReport model for individual font validation results
- ValidateCommand.validate_collection method

### Fixed
- Windows compatibility for collection extraction
- Various test fixes unrelated to collection validation

## [0.2.6] - 2026-01-05

### Added
- Apple dfont collection support
- DfontParser for reading dfont format
- DfontBuilder for writing dfont format
- Proper handling of dfont as collection in info command

### Fixed
- Spec refactor for rubocop compliance
- Re-enabled previously skipped specs

## [0.2.5] - 2026-01-03

### Added
- Font validation framework
- Validator DSL for defining validation checks
- Predefined validation profiles (indexability, usability, production, web, spec_compliance)
- ValidationReport model with structured results
- 56 validation helper methods across 8 OpenType tables
- ValidateCommand with comprehensive CLI options

### Changed
- Improved lazy loading performance
- Removed page size alignment (was causing performance issues)

## [0.2.4] - 2026-01-03

### Fixed
- Subroutine-related issues
- Spec fixes
- Glyph builder fixes
- Test font fixtures for validation testing

### Added
- Color fonts support (COLR/CPAL tables)
- WOFF/WOFF2 conversion support
- WOFF/WOFF2 info command support
- WOFF2 validation support
- ColorGlyph, ColorLayer, ColorPalette models
- BitmapGlyph, BitmapStrike models
- SvgGlyph model
- CBLC, CBDT, COLR, CPAL, sbix, SVG table support

## [0.2.3] - 2025-12-30

### Added
- WOFF/WOFF2 font version display
- WOFF2 validation checks
- Proper TTC/OTC content info handling
- Collection info displays all fonts with metadata

## [0.2.2] - 2025-12-30

### Added
- Brief mode for font info command (`--brief` flag)
- 5x faster font indexing using metadata loading mode
- Only 13 essential attributes in brief mode
- Support for 5x performance improvement in batch processing

### Changed
- README refactor for better organization

## [0.2.1] - 2025-12-28

### Added
- Proper font hinting implementation
- Bidirectional TrueType <-> PostScript hint conversion
- HintValidator for validating converted hints
- TrueTypeInstructionAnalyzer for analyzing instructions
- TrueTypeInstructionGenerator for generating instructions
- Hint round-trip validation
- CFF2 variable font support for PostScript hints

## [0.2.0] - 2025-12-17

### Added
- Initial release of Fontisan
- Basic font conversion capabilities
- Font information display
- TTC/OTC collection support
- Basic validation framework
