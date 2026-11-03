# frozen_string_literal: true

module Fontisan
  module Variation
    # Generates static font instances from variable fonts
    #
    # This class creates static font instances by applying variation deltas
    # at specific design space coordinates. It supports both TrueType (gvar)
    # and PostScript (CFF2) variable fonts.
    #
    # Process:
    # 1. Extract variation data (axes, deltas, regions)
    # 2. Calculate interpolation scalars for given coordinates
    # 3. Apply deltas to outlines (gvar or CFF2)
    # 4. Apply deltas to metrics (HVAR, VVAR, MVAR)
    # 5. Remove variation tables to create static font
    #
    # @example Generating an instance at specific coordinates
    #   generator = Fontisan::Variation::InstanceGenerator.new(font, { "wght" => 700.0 })
    #   instance_tables = generator.generate
    #
    # @example Generating a named instance
    #   generator = Fontisan::Variation::InstanceGenerator.new(font)
    #   instance_tables = generator.generate_named_instance(0)
    class InstanceGenerator
      include TableAccessor

      # @return [TrueTypeFont, OpenTypeFont] Variable font
      attr_reader :font

      # @return [Hash<String, Float>] Design space coordinates
      attr_reader :coordinates

      # @return [VariationContext] Variation context
      attr_reader :context

      # Initialize generator with font and optional coordinates
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      # @param coordinates [Hash<String, Float>] Design space coordinates (axis tag => value)
      # @param options [Hash] Options
      # @option options [Boolean] :skip_validation Skip context validation (default: false)
      def initialize(font, coordinates = {}, options = {})
        @font = font
        @coordinates = coordinates

        # Initialize variation context
        @context = VariationContext.new(@font)
        @context.validate! unless options[:skip_validation]

        # Initialize table cache for lazy loading
        @variation_tables = {}
      end

      # Generate static font instance
      #
      # Applies gvar/HVAR deltas at the coordinates to the outlines and
      # metrics and drops the variation tables. TrueType (gvar) fonts only.
      #
      # @return [Hash<String, String>] Map of table tags to binary data
      def generate
        Instancing::TrueTypeInstancer.new(@font.table_data, @coordinates).call
      end

      # Generate a named instance
      #
      # @param instance_index [Integer] Index of named instance in fvar table
      # @return [Hash<String, String>] Map of table tags to binary data
      def generate_named_instance(instance_index)
        # Extract instance coordinates from fvar
        return generate if instance_index.nil? || !@context.fvar

        instances = @context.fvar.instances
        return generate if instance_index >= instances.length

        instance = instances[instance_index]
        @coordinates = build_coordinates_from_instance(instance, @context.axes)

        generate
      end

      # Interpolate a single value
      #
      # @param base_value [Numeric] Base value
      # @param deltas [Array<Numeric>] Delta values
      # @param scalars [Array<Float>] Region scalars
      # @return [Float] Interpolated value
      def interpolate_value(base_value, deltas, scalars)
        @context.interpolator.interpolate_value(base_value, deltas, scalars)
      end

      # Interpolate a point
      #
      # @param base_point [Hash] Base point with :x and :y
      # @param delta_points [Array<Hash>] Delta points
      # @param scalars [Array<Float>] Region scalars
      # @return [Hash] Interpolated point
      def interpolate_point(base_point, delta_points, scalars)
        @context.interpolator.interpolate_point(base_point, delta_points,
                                                scalars)
      end

      private

      # Build coordinates hash from instance
      #
      # @param instance [Hash] Instance data from fvar
      # @param axes [Array<VariationAxisRecord>] Variation axes
      # @return [Hash<String, Float>] Coordinates hash
      def build_coordinates_from_instance(instance, axes)
        coordinates = {}
        instance[:coordinates].each_with_index do |value, index|
          next if index >= axes.length

          axis = axes[index]
          coordinates[axis.axis_tag] = value
        end
        coordinates
      end
    end
  end
end
