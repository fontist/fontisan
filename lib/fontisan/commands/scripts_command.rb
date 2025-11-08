# frozen_string_literal: true

require "set"
require "yaml"
require_relative "base_command"
require_relative "../models/scripts_info"

module Fontisan
  module Commands
    # Command to extract and display scripts from GSUB/GPOS tables
    class ScriptsCommand < BaseCommand
      def run
        result = Models::ScriptsInfo.new
        scripts_set = Set.new

        # Collect scripts from GSUB table
        if font.has_table?(Constants::GSUB_TAG)
          gsub = font.table(Constants::GSUB_TAG)
          scripts_set.merge(gsub.scripts)
        end

        # Collect scripts from GPOS table
        if font.has_table?(Constants::GPOS_TAG)
          gpos = font.table(Constants::GPOS_TAG)
          scripts_set.merge(gpos.scripts)
        end

        # Load script descriptions from configuration
        descriptions = load_script_descriptions

        # Build script records
        result.scripts = scripts_set.sort.map do |tag|
          Models::ScriptRecord.new(
            tag: tag,
            description: descriptions[tag] || "Unknown script",
          )
        end

        result.script_count = result.scripts.length
        result
      end

      private

      def load_script_descriptions
        config_path = File.join(
          File.dirname(__FILE__),
          "..",
          "config",
          "scripts.yml",
        )
        YAML.load_file(config_path)
      rescue StandardError => e
        warn "Warning: Could not load script descriptions: #{e.message}"
        {}
      end
    end
  end
end
