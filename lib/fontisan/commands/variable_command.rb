# frozen_string_literal: true

require_relative "base_command"
require_relative "../variation/inspector"

module Fontisan
  module Commands
    # Command to extract variable font information.
    #
    # This command extracts variation axes and named instances from variable
    # fonts using the fvar (Font Variations) table. It also provides
    # detailed inspection capabilities through the Inspector class.
    #
    # @example Extract variable font information
    #   command = VariableCommand.new("path/to/variable-font.ttf")
    #   info = command.run
    #   puts info.axes.first.tag
    #
    # @example Inspect variable font structure
    #   command = VariableCommand.new("path/to/variable-font.ttf")
    #   command.inspect(format: "json")
    class VariableCommand < BaseCommand
      # Extract variable font information from the fvar table.
      #
      # @return [Models::VariableFontInfo] Variable font information
      def run
        result = Models::VariableFontInfo.new

        # Check if font has fvar table
        unless font.has_table?(Constants::FVAR_TAG)
          result.is_variable = false
          result.axis_count = 0
          result.instance_count = 0
          result.axes = []
          result.instances = []
          return result
        end

        fvar_table = font.table(Constants::FVAR_TAG)
        name_table = font.table(Constants::NAME_TAG) if font.has_table?(Constants::NAME_TAG)

        result.is_variable = true
        result.axis_count = fvar_table.axis_count
        result.instance_count = fvar_table.instance_count

        # Extract axes information
        result.axes = fvar_table.axes.map do |axis|
          Models::AxisInfo.new(
            tag: axis.axis_tag,
            name: name_table&.english_name(axis.axis_name_id),
            min_value: axis.min_value,
            default_value: axis.default_value,
            max_value: axis.max_value,
          )
        end

        # Extract instances information
        result.instances = fvar_table.instances.map do |instance|
          Models::InstanceInfo.new(
            name: name_table&.english_name(instance[:name_id]),
            coordinates: instance[:coordinates],
          )
        end

        result
      end

      # Inspect variable font structure
      #
      # Provides detailed analysis of variable font structure including
      # axes, instances, regions, and statistics.
      #
      # @param options [Hash] Inspection options
      # @option options [String] :format Output format ("json" or "yaml")
      # @return [String] Formatted inspection output
      def inspect(options = {})
        inspector = Variation::Inspector.new(font)

        format = options[:format] || "json"

        case format.downcase
        when "yaml"
          inspector.export_yaml
        else
          inspector.export_json
        end
      end
    end
  end
end
