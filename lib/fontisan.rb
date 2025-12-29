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
require "lutaml/model/xml_adapter/nokogiri_adapter"

# Configure lutaml-model to use Nokogiri adapter for XML serialization
Lutaml::Model::Config.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter

# Core
require_relative "fontisan/version"
require_relative "fontisan/error"
require_relative "fontisan/constants"

# Binary structures and parsers
require_relative "fontisan/parsers/tag"
require_relative "fontisan/binary/base_record"

# Table parsers
require_relative "fontisan/tables/head"
require_relative "fontisan/tables/hhea"
require_relative "fontisan/tables/hmtx"
require_relative "fontisan/tables/maxp"
require_relative "fontisan/tables/loca"
require_relative "fontisan/tables/glyf"
require_relative "fontisan/tables/name"
require_relative "fontisan/tables/os2"
require_relative "fontisan/tables/post"
require_relative "fontisan/tables/cmap"
require_relative "fontisan/tables/fvar"
require_relative "fontisan/tables/variation_common"
require_relative "fontisan/tables/hvar"
require_relative "fontisan/tables/vvar"
require_relative "fontisan/tables/mvar"
require_relative "fontisan/tables/gvar"
require_relative "fontisan/tables/cvar"
require_relative "fontisan/tables/cff"
require_relative "fontisan/tables/layout_common"
require_relative "fontisan/tables/gsub"
require_relative "fontisan/tables/gpos"

# Domain objects (BinData::Record)
require_relative "fontisan/true_type_font"
require_relative "fontisan/open_type_font"
require_relative "fontisan/true_type_collection"
require_relative "fontisan/open_type_collection"
require_relative "fontisan/woff_font"
require_relative "fontisan/woff2_font"

# Font extensions for table-based construction
require_relative "fontisan/true_type_font_extensions"
require_relative "fontisan/open_type_font_extensions"

# Font loading
require_relative "fontisan/font_loader"

# Utilities
require_relative "fontisan/metrics_calculator"
require_relative "fontisan/glyph_accessor"
require_relative "fontisan/outline_extractor"
require_relative "fontisan/utilities/checksum_calculator"
require_relative "fontisan/font_writer"

# Information models (Lutaml::Model)
require_relative "fontisan/models/font_info"
require_relative "fontisan/models/table_info"
require_relative "fontisan/models/glyph_info"
require_relative "fontisan/models/glyph_outline"
require_relative "fontisan/models/unicode_mappings"
require_relative "fontisan/models/variable_font_info"
require_relative "fontisan/models/optical_size_info"
require_relative "fontisan/models/scripts_info"
require_relative "fontisan/models/features_info"
require_relative "fontisan/models/all_scripts_features_info"
require_relative "fontisan/models/validation_report"
require_relative "fontisan/models/font_export"
require_relative "fontisan/models/collection_font_summary"
require_relative "fontisan/models/collection_info"
require_relative "fontisan/models/collection_list_info"
require_relative "fontisan/models/font_summary"
require_relative "fontisan/models/table_sharing_info"

# Export infrastructure
require_relative "fontisan/export/table_serializer"
require_relative "fontisan/export/ttx_generator"
require_relative "fontisan/export/ttx_parser"
require_relative "fontisan/export/exporter"

# Validation infrastructure
require_relative "fontisan/validation/table_validator"
require_relative "fontisan/validation/structure_validator"
require_relative "fontisan/validation/consistency_validator"
require_relative "fontisan/validation/checksum_validator"
require_relative "fontisan/validation/validator"

# Subsetting infrastructure
require_relative "fontisan/subset/options"
require_relative "fontisan/subset/profile"
require_relative "fontisan/subset/glyph_mapping"
require_relative "fontisan/subset/table_subsetter"
require_relative "fontisan/subset/builder"

# Collection infrastructure
require_relative "fontisan/collection/table_analyzer"
require_relative "fontisan/collection/table_deduplicator"
require_relative "fontisan/collection/offset_calculator"
require_relative "fontisan/collection/writer"
require_relative "fontisan/collection/builder"

# Format conversion infrastructure
require_relative "fontisan/converters/conversion_strategy"
require_relative "fontisan/converters/table_copier"
require_relative "fontisan/converters/outline_converter"
require_relative "fontisan/converters/format_converter"

# Variation infrastructure
require_relative "fontisan/variation/interpolator"
require_relative "fontisan/variation/region_matcher"
require_relative "fontisan/variation/data_extractor"
require_relative "fontisan/variation/instance_generator"
require_relative "fontisan/variation/metrics_adjuster"
require_relative "fontisan/variation/converter"
require_relative "fontisan/variation/variation_preserver"
require_relative "fontisan/variation/delta_parser"
require_relative "fontisan/variation/delta_applier"
require_relative "fontisan/variation/blend_applier"
require_relative "fontisan/variation/variable_svg_generator"

# Pipeline infrastructure
require_relative "fontisan/pipeline/format_detector"
require_relative "fontisan/pipeline/variation_resolver"
require_relative "fontisan/pipeline/output_writer"
require_relative "fontisan/pipeline/transformation_pipeline"

# Optimization infrastructure
require_relative "fontisan/optimizers/pattern_analyzer"
require_relative "fontisan/optimizers/subroutine_builder"
require_relative "fontisan/optimizers/charstring_rewriter"
require_relative "fontisan/optimizers/subroutine_optimizer"
require_relative "fontisan/optimizers/subroutine_generator"

# Hints infrastructure
require_relative "fontisan/models/hint"
require_relative "fontisan/hints/truetype_instruction_analyzer"
require_relative "fontisan/hints/truetype_instruction_generator"
require_relative "fontisan/hints/truetype_hint_extractor"
require_relative "fontisan/hints/truetype_hint_applier"
require_relative "fontisan/hints/postscript_hint_extractor"
require_relative "fontisan/hints/postscript_hint_applier"
require_relative "fontisan/hints/hint_converter"
require_relative "fontisan/hints/hint_validator"

# Commands
require_relative "fontisan/commands/base_command"
require_relative "fontisan/commands/info_command"
require_relative "fontisan/commands/ls_command"
require_relative "fontisan/commands/tables_command"
require_relative "fontisan/commands/glyphs_command"
require_relative "fontisan/commands/unicode_command"
require_relative "fontisan/commands/variable_command"
require_relative "fontisan/commands/optical_size_command"
require_relative "fontisan/commands/scripts_command"
require_relative "fontisan/commands/features_command"
require_relative "fontisan/commands/dump_table_command"
require_relative "fontisan/commands/subset_command"
require_relative "fontisan/commands/convert_command"
require_relative "fontisan/commands/pack_command"
require_relative "fontisan/commands/unpack_command"
require_relative "fontisan/commands/validate_command"

# Formatters
require_relative "fontisan/formatters/text_formatter"

# CLI
require_relative "fontisan/cli"

module Fontisan
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
end
