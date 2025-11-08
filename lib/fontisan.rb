# frozen_string_literal: true

require "logger"
require "lutaml/model"

# Core
require_relative "fontisan/version"
require_relative "fontisan/error"
require_relative "fontisan/constants"

# Binary structures and parsers
require_relative "fontisan/parsers/tag"
require_relative "fontisan/binary/base_record"

# Table parsers
require_relative "fontisan/tables/head"
require_relative "fontisan/tables/name"
require_relative "fontisan/tables/os2"
require_relative "fontisan/tables/post"
require_relative "fontisan/tables/cmap"
require_relative "fontisan/tables/fvar"
require_relative "fontisan/tables/layout_common"
require_relative "fontisan/tables/gsub"
require_relative "fontisan/tables/gpos"

# Domain objects (BinData::Record)
require_relative "fontisan/true_type_font"
require_relative "fontisan/open_type_font"
require_relative "fontisan/true_type_collection"
require_relative "fontisan/open_type_collection"

# Font loading
require_relative "fontisan/font_loader"

# Utilities
require_relative "fontisan/utilities/checksum_calculator"

# Information models (Lutaml::Model)
require_relative "fontisan/models/font_info"
require_relative "fontisan/models/table_info"
require_relative "fontisan/models/glyph_info"
require_relative "fontisan/models/unicode_mappings"
require_relative "fontisan/models/variable_font_info"
require_relative "fontisan/models/optical_size_info"
require_relative "fontisan/models/scripts_info"
require_relative "fontisan/models/features_info"
require_relative "fontisan/models/all_scripts_features_info"

# Commands
require_relative "fontisan/commands/base_command"
require_relative "fontisan/commands/info_command"
require_relative "fontisan/commands/tables_command"
require_relative "fontisan/commands/glyphs_command"
require_relative "fontisan/commands/unicode_command"
require_relative "fontisan/commands/variable_command"
require_relative "fontisan/commands/optical_size_command"
require_relative "fontisan/commands/scripts_command"
require_relative "fontisan/commands/features_command"
require_relative "fontisan/commands/dump_table_command"

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
