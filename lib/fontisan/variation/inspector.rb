# frozen_string_literal: true

require "json"
require "yaml"
require_relative "variation_context"

module Fontisan
  module Variation
    # Inspects and analyzes variable font structure
    #
    # This class provides comprehensive analysis of variable font structure,
    # including axes, instances, regions, and variation statistics. Results
    # can be exported to JSON or YAML formats.
    #
    # @example Inspecting a variable font
    #   inspector = Fontisan::Variation::Inspector.new(font)
    #   info = inspector.inspect_variation
    #   # => { axes: [...], instances: [...], regions: {...}, statistics: {...} }
    #
    # @example Exporting to JSON
    #   inspector.export_json
    #   # => "{ \"axes\": [...], ... }"
    #
    # @example Exporting to YAML
    #   inspector.export_yaml
    #   # => "---\naxes:\n  - ..."
    class Inspector
      # @return [TrueTypeFont, OpenTypeFont] Font to inspect
      attr_reader :font

      # @return [VariationContext] Variation context
      attr_reader :context

      # Initialize inspector
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      def initialize(font)
        @font = font
        @context = VariationContext.new(font)
      end

      # Inspect complete variation structure
      #
      # Returns comprehensive information about font variation capabilities.
      #
      # @return [Hash] Complete variation information
      def inspect_variation
        {
          axes: inspect_axes,
          instances: inspect_instances,
          regions: inspect_regions,
          statistics: calculate_statistics,
        }
      end

      # Export inspection results as JSON
      #
      # @return [String] JSON formatted output
      def export_json
        JSON.pretty_generate(inspect_variation)
      end

      # Export inspection results as YAML
      #
      # @return [String] YAML formatted output
      def export_yaml
        YAML.dump(inspect_variation)
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if font has variation tables
      def variable_font?
        @context.variable_font?
      end

      private

      # Inspect variation axes
      #
      # @return [Array<Hash>] Array of axis information
      def inspect_axes
        return [] unless variable_font?
        return [] unless @context.fvar

        @context.axes.map do |axis|
          {
            tag: axis.axis_tag,
            name: axis_name(axis.axis_name_id),
            min: axis.min_value,
            default: axis.default_value,
            max: axis.max_value,
            hidden: axis.flags & 0x0001 != 0,
          }
        end
      end

      # Inspect named instances
      #
      # @return [Array<Hash>] Array of instance information
      def inspect_instances
        return [] unless variable_font?
        return [] unless @context.fvar

        @context.fvar.instances.map.with_index do |instance, index|
          {
            index: index,
            name: instance_name(instance[:subfamily_name_id]),
            postscript_name: instance_name(instance[:postscript_name_id]),
            coordinates: instance_coordinates(instance[:coordinates], @context.axes),
          }
        end
      end

      # Inspect variation regions
      #
      # @return [Hash] Region statistics and information
      def inspect_regions
        regions = {
          gvar: nil,
          hvar: nil,
          vvar: nil,
          mvar: nil,
        }

        if @font.has_table?("gvar")
          regions[:gvar] = inspect_gvar_regions
        end

        if @font.has_table?("HVAR")
          regions[:hvar] = inspect_hvar_regions
        end

        if @font.has_table?("VVAR")
          regions[:vvar] = inspect_vvar_regions
        end

        if @font.has_table?("MVAR")
          regions[:mvar] = inspect_mvar_regions
        end

        regions.compact
      end

      # Inspect gvar table regions
      #
      # @return [Hash] Gvar region information
      def inspect_gvar_regions
        gvar = @font.table("gvar")
        return nil unless gvar

        {
          glyph_count: gvar.glyph_count,
          axis_count: gvar.axis_count,
          shared_tuples: gvar.shared_tuple_count || 0,
          glyph_variation_data_present: gvar.glyph_count.positive?,
        }
      end

      # Inspect HVAR table regions
      #
      # @return [Hash] HVAR region information
      def inspect_hvar_regions
        hvar = @font.table("HVAR")
        return nil unless hvar

        {
          advance_width_mapping: hvar.advance_width_mapping ? true : false,
          lsb_mapping: hvar.lsb_mapping ? true : false,
          rsb_mapping: hvar.rsb_mapping ? true : false,
        }
      end

      # Inspect VVAR table regions
      #
      # @return [Hash] VVAR region information
      def inspect_vvar_regions
        vvar = @font.table("VVAR")
        return nil unless vvar

        {
          advance_height_mapping: vvar.advance_height_mapping ? true : false,
          tsb_mapping: vvar.tsb_mapping ? true : false,
          bsb_mapping: vvar.bsb_mapping ? true : false,
        }
      end

      # Inspect MVAR table regions
      #
      # @return [Hash] MVAR region information
      def inspect_mvar_regions
        mvar = @font.table("MVAR")
        return nil unless mvar

        {
          value_record_count: mvar.value_record_count || 0,
          metrics_varied: mvar.value_records&.map { |r| r[:value_tag] } || [],
        }
      end

      # Calculate variation statistics
      #
      # @return [Hash] Statistical information
      def calculate_statistics
        stats = {
          is_variable: variable_font?,
          axis_count: 0,
          instance_count: 0,
          has_glyph_variations: @context.has_glyph_variations?,
          has_metrics_variations: @context.has_metrics_variations?,
          variation_tables: [],
        }

        if variable_font?
          stats[:axis_count] = @context.axis_count
          stats[:instance_count] = @context.fvar.instance_count if @context.fvar
        end

        # List variation tables present
        variation_table_tags = %w[fvar gvar cvar HVAR VVAR MVAR avar STAT]
        stats[:variation_tables] = variation_table_tags.select do |tag|
          @font.has_table?(tag)
        end

        # Calculate design space size
        if stats[:axis_count].positive?
          stats[:design_space_dimensions] = stats[:axis_count]
        end

        stats
      end

      # Get axis name from name table
      #
      # @param name_id [Integer] Name ID
      # @return [String] Axis name
      def axis_name(name_id)
        return "Unknown" unless @font.has_table?("name")

        name_table = @font.table("name")
        record = name_table.names.find { |n| n[:name_id] == name_id }
        record ? record[:string] : "Axis #{name_id}"
      end

      # Get instance name from name table
      #
      # @param name_id [Integer] Name ID
      # @return [String, nil] Instance name
      def instance_name(name_id)
        return nil unless name_id
        return nil unless @font.has_table?("name")

        name_table = @font.table("name")
        record = name_table.names.find { |n| n[:name_id] == name_id }
        record ? record[:string] : "Instance #{name_id}"
      end

      # Build coordinates hash from instance
      #
      # @param coordinates [Array<Float>] Coordinate values
      # @param axes [Array] Variation axes
      # @return [Hash<String, Float>] Coordinates by axis tag
      def instance_coordinates(coordinates, axes)
        coords = {}
        coordinates.each_with_index do |value, index|
          break if index >= axes.length

          axis = axes[index]
          coords[axis.axis_tag] = value
        end
        coords
      end
    end
  end
end
