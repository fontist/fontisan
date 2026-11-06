# frozen_string_literal: true

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

      # Initialize the instancer
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font object
      # @raise [ArgumentError] If font is not a variable font
      def initialize(font)
        @font = font
        validate_variable_font!
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
      def instance(user_coords, _options = {})
        Fontisan::Engine.record_ruby(:instance)
        tables = Variation::Instancing::TrueTypeInstancer
          .new(@font.table_data, user_coords).call
        FontWriter.write_font(tables)
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
        fvar = @font.table_data["fvar"]
        names = if @font.table_data["name"]
                  Variation::Instancing::NameRewriter.new(@font.table_data["name"])
                end
        tags = axis_tags
        Variation::Instancing::AxisSpace.named_instances(fvar).map do |inst|
          {
            name_id: inst[:name_id],
            name: names&.lookup(inst[:name_id]) || "Instance #{inst[:name_id]}",
            coordinates: tags.zip(inst[:values]).to_h,
          }
        end
      end

      # Check if font is a variable font
      #
      # @return [Boolean] True if variable font
      def variable_font?
        true
      end

      # Get available axis information
      #
      # @return [Array<Variation::Instancing::AxisSpace::Axis>]
      def axes
        axis_space.axes
      end

      # Get available axis tags
      #
      # @return [Array<String>] Array of axis tags
      def axis_tags
        axis_space.tags
      end

      private

      # Validate that font is a variable font
      #
      # @raise [ArgumentError] If not a variable font
      def validate_variable_font!
        fvar_data = @font.table_data["fvar"]
        return unless fvar_data.nil? || fvar_data.empty?

        raise ArgumentError, "Font is not a variable font (missing fvar table)"
      end

      def axis_space
        @axis_space ||= Variation::Instancing::AxisSpace.new(
          @font.table_data["fvar"], @font.table_data["avar"]
        )
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
    end
  end
end
