# frozen_string_literal: true

require "set"
require "yaml"
require_relative "base_command"
require_relative "../models/features_info"
require_relative "../models/all_scripts_features_info"

module Fontisan
  module Commands
    # Command to extract and display features from GSUB/GPOS tables
    class FeaturesCommand < BaseCommand
      def run
        script = @options[:script]

        # If no script specified, show features for all scripts
        return features_for_all_scripts unless script

        # Show features for specific script
        features_for_script(script)
      end

      private

      def features_for_script(script)
        result = Models::FeaturesInfo.new
        result.script = script
        features_set = Set.new

        # Collect features from GSUB table
        if font.has_table?(Constants::GSUB_TAG)
          gsub = font.table(Constants::GSUB_TAG)
          features_set.merge(gsub.features(script_tag: script))
        end

        # Collect features from GPOS table
        if font.has_table?(Constants::GPOS_TAG)
          gpos = font.table(Constants::GPOS_TAG)
          features_set.merge(gpos.features(script_tag: script))
        end

        # Load feature descriptions
        descriptions = load_feature_descriptions

        # Build feature records
        result.features = features_set.sort.map do |tag|
          Models::FeatureRecord.new(
            tag: tag,
            description: descriptions[tag] || "Unknown feature",
          )
        end

        result.feature_count = result.features.length
        result
      end

      def features_for_all_scripts
        result = Models::AllScriptsFeaturesInfo.new
        scripts_set = Set.new

        # Collect all scripts
        if font.has_table?(Constants::GSUB_TAG)
          gsub = font.table(Constants::GSUB_TAG)
          scripts_set.merge(gsub.scripts)
        end

        if font.has_table?(Constants::GPOS_TAG)
          gpos = font.table(Constants::GPOS_TAG)
          scripts_set.merge(gpos.scripts)
        end

        # Get features for each script
        result.scripts_features = scripts_set.sort.map do |script_tag|
          features_for_script(script_tag)
        end

        result
      end

      def load_feature_descriptions
        config_path = File.join(
          File.dirname(__FILE__),
          "..",
          "config",
          "features.yml",
        )
        YAML.load_file(config_path)
      rescue StandardError => e
        warn "Warning: Could not load feature descriptions: #{e.message}"
        {}
      end
    end
  end
end
