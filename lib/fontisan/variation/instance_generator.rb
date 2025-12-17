# frozen_string_literal: true

require_relative "interpolator"
require_relative "region_matcher"
require_relative "metrics_adjuster"
require_relative "variation_context"
require_relative "table_accessor"

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
      # Applies variation deltas and returns static font tables.
      #
      # @return [Hash<String, String>] Map of table tags to binary data
      def generate
        # Start with base font tables
        tables = @font.table_data.dup

        # Determine variation type
        if has_variation_table?("gvar")
          # TrueType outlines with gvar
          apply_gvar_deltas(tables)
        elsif has_variation_table?("CFF2")
          # PostScript outlines with CFF2 blend
          apply_cff2_blend(tables)
        end

        # Apply metrics variations if present
        apply_metrics_deltas(tables) if @context.has_metrics_variations?

        # Remove variation-specific tables to create static font
        remove_variation_tables(tables)

        tables
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

      # Apply gvar deltas to TrueType outlines
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_gvar_deltas(_tables)
        gvar = variation_table("gvar")
        glyf = @font.table("glyf")
        return unless gvar && glyf

        # Get glyph count
        maxp = @font.table("maxp")
        glyph_count = maxp ? maxp.num_glyphs : gvar.glyph_count

        # Process each glyph
        glyph_count.times do |glyph_id|
          apply_glyph_deltas(glyph_id, gvar, glyf)
        end

        # Rebuild glyf and loca tables with adjusted outlines
        # This is a placeholder - full implementation would reconstruct tables
      end

      # Apply deltas to a specific glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param gvar [Gvar] Gvar table
      # @param glyf [Glyf] Glyf table
      def apply_glyph_deltas(glyph_id, gvar, _glyf)
        # Get tuple variations for this glyph
        tuple_data = gvar.glyph_tuple_variations(glyph_id)
        return unless tuple_data

        # Match tuples to current coordinates
        matches = @context.region_matcher.match_tuples(
          coordinates: @coordinates,
          tuples: tuple_data[:tuples],
        )

        nil if matches.empty?

        # Get base glyph outline
        # Apply matched deltas with their scalars
        # This is a placeholder - full implementation would:
        # 1. Parse glyph outline points
        # 2. Parse delta data for each tuple
        # 3. Apply: new_point = base_point + Σ(delta * scalar)
        # 4. Update glyph outline
      end

      # Apply CFF2 blend operators
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_cff2_blend(_tables)
        cff2 = variation_table("CFF2")
        return unless cff2

        # Set number of axes for CFF2
        cff2.num_axes = @context.axis_count

        # Process each glyph's CharString
        glyph_count = cff2.glyph_count
        return if glyph_count.zero?

        # Calculate variation scalars once
        calculate_variation_scalars

        # Apply blend to each glyph
        # This is a placeholder - full implementation would:
        # 1. Parse CharString with blend operators
        # 2. Apply scalars to blend operands
        # 3. Rebuild CharStrings without blend operators
        # 4. Update CFF2 table
      end

      # Calculate variation scalars for current coordinates
      #
      # @return [Array<Float>] Scalars for each axis
      def calculate_variation_scalars
        @context.axes.map do |axis|
          coord = @coordinates[axis.axis_tag] || axis.default_value
          @context.interpolator.normalize_coordinate(coord, axis.axis_tag)
        end
      end

      # Apply metrics variations
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_metrics_deltas(tables)
        # Apply HVAR (horizontal metrics)
        apply_hvar_deltas(tables) if has_variation_table?("HVAR")

        # Apply VVAR (vertical metrics)
        apply_vvar_deltas(tables) if has_variation_table?("VVAR")

        # Apply MVAR (font-wide metrics)
        apply_mvar_deltas(tables) if has_variation_table?("MVAR")
      end

      # Apply HVAR deltas to horizontal metrics
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_hvar_deltas(_tables)
        adjuster = MetricsAdjuster.new(@font, @context.interpolator)
        adjuster.apply_hvar_deltas(@coordinates)
      end

      # Apply VVAR deltas to vertical metrics
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_vvar_deltas(_tables)
        adjuster = MetricsAdjuster.new(@font, @context.interpolator)
        adjuster.apply_vvar_deltas(@coordinates)
      end

      # Apply MVAR deltas to font-wide metrics
      #
      # @param tables [Hash<String, String>] Font tables
      def apply_mvar_deltas(_tables)
        adjuster = MetricsAdjuster.new(@font, @context.interpolator)
        adjuster.apply_mvar_deltas(@coordinates)
      end

      # Remove variation tables from static font
      #
      # @param tables [Hash<String, String>] Font tables
      def remove_variation_tables(tables)
        variation_tables = %w[fvar gvar cvar HVAR VVAR MVAR avar STAT]
        variation_tables.each { |tag| tables.delete(tag) }
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
        @context.interpolator.interpolate_point(base_point, delta_points, scalars)
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
