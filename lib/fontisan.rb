# frozen_string_literal: true

#                                                                     _____
#                         _____
#        _____
#       |     | <-----------------------|     | font body
#       |     |(font)                  |     |
#       |     |header                  |     |
#       |     |
#      \ \ \ \--> body data
#       | | | |
#       |_| |_|
#                          ^
#                          |
#                          ... meta data opposite the table headers
#                           data (instance variable bytes)
#                     ...
# Coupling rules:
#  - a trueType font is composed of only one header and all 15
#  - a head table has one of only two appearance... base and non zero top bit (mac format.k)
#  - The most critical tables are
#      - head       # header table
#      - hmtx       # metrics array
#      - post       # glyph names
#      - cmap       # unicode mappings
#      - /LOCA      # glyph offsets
#      - glyf       # glyph outlines
#    Without these you wouldn't be able to decode the font.
#  - the only two required tables are head and cmap

require "logger"
require "bindata"
require "zlib"
require "stringio"
require "lutaml/model"

# Configure lutaml-model to use Nokogiri adapter for XML serialization
Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type = :nokogiri
end

module Fontisan
  #
  # Each namespace under Fontisan has a hub file at lib/fontisan/<ns>.rb
  # that declares autoloads for its children. This file autoloads those
  # hubs plus the flat Fontisan::* classes. Files are loaded lazily on
  # first reference.

  # Core
  require "fontisan/version"
  autoload :Constants, "fontisan/constants"
  autoload :LoadingModes, "fontisan/loading_modes"
  autoload :ConversionOptions, "fontisan/conversion_options"

  # Errors (all defined in fontisan/error)
  autoload :Error, "fontisan/error"
  autoload :InvalidFontError, "fontisan/error"
  autoload :UnsupportedFormatError, "fontisan/error"
  autoload :CorruptedTableError, "fontisan/error"
  autoload :MissingTableError, "fontisan/error"
  autoload :ParseError, "fontisan/error"
  autoload :SubsettingError, "fontisan/error"
  autoload :VariationError, "fontisan/error"
  autoload :InvalidCoordinatesError, "fontisan/error"
  autoload :MissingVariationTableError, "fontisan/error"
  autoload :InvalidAxisError, "fontisan/error"
  autoload :RegionOverlapError, "fontisan/error"
  autoload :DeltaMismatchError, "fontisan/error"
  autoload :InvalidInstanceIndexError, "fontisan/error"
  autoload :CorruptedVariationDataError, "fontisan/error"
  autoload :InvalidVariationDataError, "fontisan/error"
  autoload :VariationDataCorruptedError, "fontisan/error"

  # Namespace hubs (each hub declares its own child autoloads)
  autoload :Audit, "fontisan/audit"
  autoload :Binary, "fontisan/binary"
  autoload :Cldr, "fontisan/cldr"
  autoload :Collection, "fontisan/collection"
  autoload :Commands, "fontisan/commands"
  autoload :Converters, "fontisan/converters"
  autoload :Export, "fontisan/export"
  autoload :Formatters, "fontisan/formatters"
  autoload :Hints, "fontisan/hints"
  autoload :Models, "fontisan/models"
  autoload :Optimizers, "fontisan/optimizers"
  autoload :Parsers, "fontisan/parsers"
  autoload :Pipeline, "fontisan/pipeline"
  autoload :Subset, "fontisan/subset"
  autoload :Svg, "fontisan/svg"
  autoload :Tables, "fontisan/tables"
  autoload :Type1, "fontisan/type1"
  autoload :Ucd, "fontisan/ucd"
  autoload :Utilities, "fontisan/utilities"
  autoload :Utils, "fontisan/utils"
  autoload :Validation, "fontisan/validation"
  autoload :Validators, "fontisan/validators"
  autoload :Variable, "fontisan/variable"
  autoload :Variation, "fontisan/variation"
  autoload :Woff2, "fontisan/woff2"

  # Flat classes (no inner namespace)
  autoload :BaseCollection, "fontisan/base_collection"
  autoload :Cli, "fontisan/cli"
  autoload :DfontCollection, "fontisan/dfont_collection"
  autoload :FontLoader, "fontisan/font_loader"
  autoload :FontWriter, "fontisan/font_writer"
  autoload :GlyphAccessor, "fontisan/glyph_accessor"
  autoload :MetricsCalculator, "fontisan/metrics_calculator"
  autoload :OpenTypeCollection, "fontisan/open_type_collection"
  autoload :OpenTypeFont, "fontisan/open_type_font"
  autoload :OpenTypeFontExtensions, "fontisan/open_type_font_extensions"
  autoload :OutlineExtractor, "fontisan/outline_extractor"
  autoload :SfntFont, "fontisan/sfnt_font"
  autoload :SfntTable, "fontisan/sfnt_table"
  autoload :TrueTypeCollection, "fontisan/true_type_collection"
  autoload :TrueTypeFont, "fontisan/true_type_font"
  autoload :TrueTypeFontExtensions, "fontisan/true_type_font_extensions"
  autoload :Type1Font, "fontisan/type1_font"
  autoload :UcdCli, "fontisan/cli/ucd_cli"
  autoload :CldrCli, "fontisan/cli/cldr_cli"
  autoload :Woff2Font, "fontisan/woff2_font"
  autoload :WoffFont, "fontisan/woff_font"

  # SFNT offset table and table directory (defined in sfnt_font.rb)
  autoload :OffsetTable, "fontisan/sfnt_font"
  autoload :TableDirectory, "fontisan/sfnt_font"

  # WOFF headers and table directory entries
  autoload :WoffHeader, "fontisan/woff_font"
  autoload :WoffTableDirectoryEntry, "fontisan/woff_font"
  autoload :Woff2TableDirectoryEntry, "fontisan/woff2_font"
  class << self
    attr_accessor :logger

    def configure
      yield self if block_given?
    end
  end

  # Set default logger
  self.logger = Logger.new($stdout).tap do |log|
    log.level = Logger::WARN
  end

  # Get font information.
  #
  # Supports both full and brief modes. Brief mode uses metadata loading for
  # 5x faster parsing by loading only essential tables (name, head, hhea,
  # maxp, OS/2, post). Returns FontInfo with 13 essential fields in brief mode
  # or all 38 fields in full mode.
  #
  # @param path [String] Path to font file
  # @param brief [Boolean] Use brief mode for fast identification (default: false)
  # @param font_index [Integer] Index for TTC/OTC files (default: 0)
  # @return [Models::FontInfo, Models::CollectionInfo, Models::CollectionBriefInfo] Font information
  #
  # @example Get full info
  #   info = Fontisan.info("font.ttf")
  #   puts info.family_name
  #   puts info.copyright  # populated in full mode
  #
  # @example Get brief info (5x faster)
  #   info = Fontisan.info("font.ttf", brief: true)
  #   puts info.family_name       # populated
  #   puts info.postscript_name   # populated
  #   puts info.copyright         # nil (not populated in brief mode)
  #
  # @example Serialize to JSON
  #   info = Fontisan.info("font.ttf", brief: true)
  #   puts info.to_json
  def self.info(path, brief: false, font_index: 0)
    Commands::InfoCommand.new(path, brief: brief, font_index: font_index).run
  end

  # Convert a font to a different format.
  #
  # Delegates to {Commands::ConvertCommand}. Format-specific compression knobs
  # are declared by each strategy (single source of truth) and forwarded
  # through the transformation pipeline.
  #
  # WOFF uses zlib and runs on every browser that supports web fonts (IE9+,
  # all evergreen browsers). WOFF2 uses Brotli for ~30% smaller output but
  # requires modern browsers — use WOFF when legacy support matters.
  #
  # @param path [String] Input font file
  # @param to [Symbol, String] Target format: :ttf, :otf, :type1, :woff,
  #   :woff2, :svg, :ttc, :otc, :dfont
  # @param output [String] Output font file path
  # @param opts [Hash] Conversion options. Format-specific knobs:
  #   - WOFF:  :zlib_level (0–9, default 6), :uncompressed (bool),
  #     :compression_threshold (bytes)
  #   - WOFF2: :brotli_quality (0–11, default 11), :transform_tables (bool)
  #   - Variable fonts: :coordinates, :instance_index, :preserve_variation
  #   - Collections: :target_format ("preserve"|"ttf"|"otf")
  # @return [Hash] Result hash with :success, :output_path, source/target
  #   format, input/output sizes, and variation strategy.
  #
  # @example TTF → WOFF2 (modern browsers)
  #   Fontisan.convert("f.ttf", to: :woff2, output: "f.woff2", brotli_quality: 11)
  #
  # @example TTF → WOFF (legacy browsers, max zlib)
  #   Fontisan.convert("f.ttf", to: :woff, output: "f.woff", zlib_level: 9)
  #
  # @example WOFF with no compression (legal per WOFF 1.0 §5.1)
  #   Fontisan.convert("f.ttf", to: :woff, output: "f.woff", uncompressed: true)
  def self.convert(path, to:, output:, **)
    Commands::ConvertCommand.new(path, { to: to, output: output, ** }).run
  end

  # Validate a font file using specified profile
  #
  # Validates fonts against quality checks, structural integrity, and OpenType
  # specification compliance using the new DSL-based validation framework.
  #
  # @param path [String] Path to font file
  # @param profile [Symbol, String] Validation profile (default: :default)
  #   Available profiles:
  #   - :indexability - Fast validation for font discovery
  #   - :usability - Basic usability for installation
  #   - :production - Comprehensive quality checks (default)
  #   - :web - Web embedding and optimization
  #   - :spec_compliance - Full OpenType spec compliance
  #   - :default - Alias for production profile
  # @param options [Hash] Additional validation options
  # @return [Models::ValidationReport] Validation report with issues and status
  #
  # @example Validate with default profile
  #   report = Fontisan.validate("font.ttf")
  #   puts "Valid: #{report.valid?}"
  #
  # @example Validate for web use
  #   report = Fontisan.validate("font.ttf", profile: :web)
  #   puts "Errors: #{report.summary.errors}"
  #
  # @example Validate and get detailed report
  #   report = Fontisan.validate("font.ttf", profile: :production)
  #   puts report.to_yaml
  def self.validate(path, profile: :default, options: {})
    # Get profile configuration
    profile_config = Validators::ProfileLoader.profile_info(profile)
    raise ArgumentError, "Unknown profile: #{profile}" unless profile_config

    # Load font with appropriate mode
    mode = profile_config[:loading_mode].to_sym
    font = FontLoader.load(path, mode: mode)

    # Load validator for profile
    validator = Validators::ProfileLoader.load(profile)

    # Run validation
    validator.validate(font)
  end

  class << self
    # Get loading mode for validation profile
    #
    # Temporarily disabled - will be reimplemented with new DSL framework
    #
    # @param profile [Symbol] Validation profile
    # @return [Symbol] Loading mode (:metadata or :full)
    # def profile_loading_mode(profile)
    #   Validation::Profile.load(profile).loading_mode.to_sym
    # rescue
    #   :full
    # end
  end
end
