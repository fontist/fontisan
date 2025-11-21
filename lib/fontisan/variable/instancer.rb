# frozen_string_literal: true

require_relative "delta_applicator"
require_relative "static_font_builder"

module Fontisan
  module Variable
    # Main entry point for variable font instancing
    #
    # This class orchestrates the complete process of generating a static
    # font instance from a variable font at specified coordinates:
    #
    # 1. Validates the font is a variable font (has fvar table)
    # 2. Normalizes user coordinates using AxisNormalizer
    # 3. Calculates region scalars using RegionMatcher
    # 4. Applies deltas using DeltaApplicator
    # 5. Builds static font using StaticFontBuilder
    #
    # @example Generate instance at specific coordinates
    #   instancer = Instancer.new(variable_font)
    #   static_binary = instancer.instance({ "wght" => 700 })
    #   File.binwrite("bold.ttf", static_binary)
    #
    # @example Generate instance for named instance
    #   instancer = Instancer.new(variable_font)
    #   static_binary = instancer.instance_named("Bold")
    class Instancer
      # @return [Object] The variable font object
      attr_reader :font

      # @return [DeltaApplicator] Delta applicator
      attr_reader :delta_applicator

      # @return [StaticFontBuilder] Static font builder
      attr_reader :static_font_builder

      # Initialize the instancer
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font object
      # @raise [ArgumentError] If font is not a variable font
      def initialize(font)
        @font = font
        validate_variable_font!

        @delta_applicator = DeltaApplicator.new(font)
        @static_font_builder = StaticFontBuilder.new(font)
      end

      # Generate static font instance at specified coordinates
      #
      # @param user_coords [Hash<String, Numeric>] User coordinates
      #   { "wght" => 700, "wdth" => 100 }
      # @param options [Hash] Instance options
      # @option options [Boolean] :update_modified Update head modified timestamp
      # @return [String] Complete static font binary
      #
      # @example
      #   binary = instancer.instance({ "wght" => 700, "wdth" => 100 })
      def instance(user_coords, options = {})
        # Apply deltas to get all varied data
        delta_result = @delta_applicator.apply(user_coords)

        # Collect varied metrics for all glyphs
        varied_metrics = collect_varied_glyph_metrics(
          delta_result[:normalized_coords],
          delta_result[:region_scalars],
        )

        # Extract font-level metrics
        font_metrics = delta_result[:font_metrics]

        # Build static font
        @static_font_builder.build(varied_metrics, font_metrics, options)
      end

      # Generate static font instance and write to file
      #
      # @param output_path [String] Output file path
      # @param user_coords [Hash<String, Numeric>] User coordinates
      # @param options [Hash] Instance options
      # @return [Integer] Number of bytes written
      #
      # @example
      #   instancer.instance_to_file("bold.ttf", { "wght" => 700 })
      def instance_to_file(output_path, user_coords, options = {})
        binary = instance(user_coords, options)
        File.binwrite(output_path, binary)
      end

      # Generate static font instance for a named instance
      #
      # @param instance_name [String] Named instance name (from fvar)
      # @param options [Hash] Instance options
      # @return [String] Complete static font binary
      # @raise [ArgumentError] If named instance not found
      #
      # @example
      #   binary = instancer.instance_named("Bold")
      def instance_named(instance_name, options = {})
        coords = find_named_instance_coords(instance_name)
        instance(coords, options)
      end

      # Generate static font instance for a named instance and write to file
      #
      # @param output_path [String] Output file path
      # @param instance_name [String] Named instance name
      # @param options [Hash] Instance options
      # @return [Integer] Number of bytes written
      #
      # @example
      #   instancer.instance_named_to_file("bold.ttf", "Bold")
      def instance_named_to_file(output_path, instance_name, options = {})
        binary = instance_named(instance_name, options)
        File.binwrite(output_path, binary)
      end

      # Get list of available named instances
      #
      # @return [Array<Hash>] Array of named instance information
      #   [{ name: "Bold", coords: { "wght" => 700 } }, ...]
      def named_instances
        fvar = load_fvar_table
        return [] unless fvar

        # Get name table for instance names
        name_table = load_name_table

        fvar.instances.map do |instance|
          coords = extract_instance_coords(instance, fvar)
          name = if name_table
                   get_instance_name(instance[:name_id],
                                     name_table)
                 end

          {
            name_id: instance[:name_id],
            name: name || "Instance #{instance[:name_id]}",
            coordinates: coords,
          }
        end
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if variable font
      def variable_font?
        @delta_applicator.variable_font?
      end

      # Get available axis information
      #
      # @return [Hash] Axis information
      def axes
        @delta_applicator.axes
      end

      # Get available axis tags
      #
      # @return [Array<String>] Array of axis tags
      def axis_tags
        @delta_applicator.axis_tags
      end

      private

      # Validate that font is a variable font
      #
      # @raise [ArgumentError] If not a variable font
      def validate_variable_font!
        fvar_data = @font.table_data("fvar")
        return unless fvar_data.nil? || fvar_data.empty?

        raise ArgumentError, "Font is not a variable font (missing fvar table)"
      end

      # Collect varied metrics for all glyphs
      #
      # @param normalized_coords [Hash] Normalized coordinates
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Hash<Integer, Hash>] Varied metrics by glyph ID
      def collect_varied_glyph_metrics(normalized_coords, _region_scalars)
        varied_metrics = {}

        # Get number of glyphs
        maxp = load_maxp_table
        return varied_metrics unless maxp

        num_glyphs = maxp.num_glyphs

        # Get original hmtx metrics
        hmtx = load_hmtx_table
        return varied_metrics unless hmtx

        # For each glyph, calculate varied metrics
        num_glyphs.times do |glyph_id|
          original_metric = hmtx.metric_for(glyph_id)
          next unless original_metric

          # Get deltas from delta applicator
          deltas = @delta_applicator.apply_glyph(glyph_id, normalized_coords)
          metric_deltas = deltas[:metric_deltas]

          # Calculate varied values
          varied_metric = {
            advance_width: original_metric[:advance_width],
            lsb: original_metric[:lsb],
          }

          # Apply horizontal deltas if present
          if metric_deltas[:horizontal]
            if metric_deltas[:horizontal][:advance_width]
              varied_metric[:advance_width] += metric_deltas[:horizontal][:advance_width]
            end

            if metric_deltas[:horizontal][:lsb]
              varied_metric[:lsb] += metric_deltas[:horizontal][:lsb]
            end
          end

          varied_metrics[glyph_id] = varied_metric
        end

        varied_metrics
      end

      # Find coordinates for a named instance
      #
      # @param instance_name [String] Instance name
      # @return [Hash<String, Float>] Coordinates
      # @raise [ArgumentError] If instance not found
      def find_named_instance_coords(instance_name)
        instances = named_instances
        instance = instances.find { |inst| inst[:name] == instance_name }

        unless instance
          raise ArgumentError,
                "Named instance '#{instance_name}' not found"
        end

        instance[:coordinates]
      end

      # Extract coordinates from instance record
      #
      # @param instance [Hash] Instance record
      # @param fvar [Fvar] fvar table
      # @return [Hash<String, Float>] Coordinates by axis tag
      def extract_instance_coords(instance, fvar)
        coords = {}
        instance[:coordinates].each_with_index do |value, index|
          axis = fvar.axes[index]
          coords[axis.axis_tag.to_s] = value if axis
        end
        coords
      end

      # Get instance name from name table
      #
      # @param name_id [Integer] Name table ID
      # @param name_table [Name] name table
      # @return [String, nil] Instance name
      def get_instance_name(name_id, name_table)
        # Try to get English name
        record = name_table.records.find do |r|
          r.name_id == name_id && r.language_id == 0x0409 # English (US)
        end

        record ||= name_table.records.find { |r| r.name_id == name_id }
        record&.value
      rescue StandardError
        nil
      end

      # Load fvar table
      #
      # @return [Fvar, nil] fvar table or nil
      def load_fvar_table
        data = @font.table_data("fvar")
        return nil if data.nil? || data.empty?

        Tables::Fvar.read(data)
      rescue StandardError
        nil
      end

      # Load name table
      #
      # @return [Name, nil] name table or nil
      def load_name_table
        data = @font.table_data("name")
        return nil if data.nil? || data.empty?

        Tables::Name.read(data)
      rescue StandardError
        nil
      end

      # Load maxp table
      #
      # @return [Maxp, nil] maxp table or nil
      def load_maxp_table
        data = @font.table_data("maxp")
        return nil if data.nil? || data.empty?

        Tables::Maxp.read(data)
      rescue StandardError
        nil
      end

      # Load hmtx table
      #
      # @return [Hmtx, nil] hmtx table or nil
      def load_hmtx_table
        data = @font.table_data("hmtx")
        return nil if data.nil? || data.empty?

        hmtx = Tables::Hmtx.read(data)

        # Parse with context
        hhea = load_hhea_table
        maxp = load_maxp_table
        return nil unless hhea && maxp

        hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
        hmtx
      rescue StandardError
        nil
      end

      # Load hhea table
      #
      # @return [Hhea, nil] hhea table or nil
      def load_hhea_table
        data = @font.table_data("hhea")
        return nil if data.nil? || data.empty?

        Tables::Hhea.read(data)
      rescue StandardError
        nil
      end
    end
  end
end
