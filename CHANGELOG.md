# Changelog

All notable changes to Fontisan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Fontisan::SvgToGlyf` — converts SVG path data (from ucode code-chart
  extraction) into `Ufo::Glyph` objects that feed directly into the
  existing Stitcher + TtfCompiler pipeline. The converter handles SVG
  path commands (M/L/H/V/C/S/Q/T/Z), relative and absolute coordinates,
  smooth-curve reflection, SVG `<g transform>` accumulation, viewBox
  coordinate normalization, and Y-axis flipping. Cubic-to-quadratic
  conversion and contour winding correction are handled automatically
  by the existing `Ufo::Compile::Filters` when compiling to TTF.
- `Fontisan::SvgToGlyf::Geometry::AffineTransform` — 2×3 matrix with
  compose/apply, used uniformly for all coordinate operations.
- `Fontisan::SvgToGlyf::Geometry::TransformParser` — parses SVG
  `transform="..."` attribute (translate, scale, rotate, matrix, skew).
- `Fontisan::SvgToGlyf::Geometry::Normalizer` — composes the viewBox →
  font UPM normalization (Y-flip + scale) with group transforms.
- `Fontisan::SvgToGlyf::Path::Parser` — tokenizes and parses SVG path
  `d` strings into typed Command objects with implicit-repetition support.
- `Fontisan::SvgToGlyf::Path::ContourBuilder` — converts commands to
  `Ufo::Contour` objects, tracking current-point, subpath-start, and
  control-point state for smooth-curve reflection.
- `Fontisan::SvgToGlyf::Document` — walks SVG XML (via Nokogiri),
  accumulating ancestor `<g>` transforms per `<path>`.
- `Fontisan::Ufo::Compile::Avar` — builds the OpenType `avar` (Axis
  Variation) table with per-axis non-linear maps (defaults to identity
  -1/0/1 mapping).
- `Fontisan::Ufo::Compile::Hvar` — builds the OpenType `HVAR`
  (Horizontal Metrics Variation) table with advance-width deltas per
  glyph.
- `Fontisan::Ufo::Compile::Mvar` — builds the OpenType `MVAR`
  (Metrics Variation) table for font-wide metric deltas (ascender,
  descender, etc.).
- `Fontisan::Ufo::Compile::Stat` — builds the OpenType `STAT` (Style
  Attributes) table with design axes, axis value tables, and elided
  fallback name ID.
- `Fontisan::Ufo::Compile::ItemVariationStore` — shared builder for
  the ItemVariationStore structure used by HVAR and MVAR
  (VariationRegionList + ItemVariationData with int8/int16 delta
  packing).
- `Fontisan::Ufo::Compile::VariableTtf` — orchestrator that compiles
  a default UFO master plus variation masters into a single variable
  TTF (emits fvar, gvar, HVAR, MVAR, avar, STAT alongside the standard
  TTF tables).
- `TtfCompiler#build_tables` — extracted public method returning the
  TTF table hash without writing, so `VariableTtf` can reuse the
  standard table pipeline.

### Fixed

- `Stitcher` silently dropped compound (composite) TrueType glyphs
  from TTF donors. The O(1) extraction path only handled `simple?`
  glyphs and returned `nil` for compounds. Compound glyphs are now
  recursively flattened (with affine transforms applied) into simple
  contours, making them self-contained. Affected donors include
  NotoSansCuneiform (U+12399), NotoSansTaiTham (594 glyphs),
  NotoSerifDivesAkuru (414), NotoSerifTaiYo (1007), and others.

### Removed

- Audit subsystem (`Fontisan::Audit`, `Fontisan::Commands::Audit*`,
  `Formatters::AuditTextRenderer` / `AuditDiffTextRenderer` /
  `LibrarySummaryTextRenderer`, `Models::Audit::*`) — moved to ucode.
  Never had external consumers.
- UCD/UCDXML subsystem (`Fontisan::Ucd`, `config/ucd.yml`) — moved to
  ucode. Never released in a published gem version.
- `fontisan audit` and `fontisan ucd` CLI subcommands.

### Added (documentation)
- Comprehensive documentation for WOFF/WOFF2 format support
- Color fonts documentation (COLR/CPAL, sbix, SVG tables)
- Font validation framework documentation
- Apple legacy font formats documentation ('true' signature, dfont)
- Font collection validation documentation
- Updated font hinting documentation
- Enhanced README with all v0.2.1-v0.2.7 features

### Changed (documentation)
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
