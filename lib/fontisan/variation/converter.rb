# frozen_string_literal: true

require_relative "interpolator"
require_relative "table_accessor"

module Fontisan
  module Variation
    # Converts variation data between TrueType (gvar) and CFF2 (blend) formats
    #
    # This class enables format conversion while preserving variation data:
    # - gvar tuples → CFF2 blend operators
    # - CFF2 blend operators → gvar tuples
    #
    # Process for gvar → blend:
    # 1. Extract tuple variations from gvar
    # 2. Map tuple regions to blend regions
    # 3. Embed blend operators in CharStrings at control points
    # 4. Encode delta values in blend format
    #
    # Process for blend → gvar:
    # 1. Parse CharStrings with blend operators
    # 2. Extract blend deltas and regions
    # 3. Map to gvar tuple format
    # 4. Build gvar table structure
    #
    # @example Converting gvar to CFF2 blend
    #   converter = VariationConverter.new(font, axes)
    #   blend_data = converter.gvar_to_blend(glyph_id)
    #
    # @example Converting CFF2 blend to gvar
    #   converter = VariationConverter.new(font, axes)
    #   tuple_data = converter.blend_to_gvar(glyph_id)
    class VariationConverter
      include TableAccessor

      # @return [TrueTypeFont, OpenTypeFont] Font instance
      attr_reader :font

      # @return [Array<VariationAxisRecord>] Variation axes
      attr_reader :axes

      # Initialize converter
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font instance
      # @param axes [Array<VariationAxisRecord>] Variation axes from fvar
      def initialize(font, axes)
        @font = font
        @axes = axes || []
        @variation_tables = {}
      end

      # Convert gvar tuples to CFF2 blend format for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Hash, nil] Blend data or nil
      def gvar_to_blend(glyph_id)
        return nil unless has_variation_table?("gvar")
        return nil unless has_variation_table?("glyf")

        gvar = variation_table("gvar")
        return nil unless gvar

        # Get tuple variations for this glyph
        tuple_data = gvar.glyph_tuple_variations(glyph_id)
        return nil unless tuple_data

        # Convert tuples to blend format
        convert_tuples_to_blend(tuple_data)
      end

      # Convert CFF2 blend operators to gvar tuple format for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Hash, nil] Tuple data or nil
      def blend_to_gvar(_glyph_id)
        return nil unless has_variation_table?("CFF2")

        cff2 = variation_table("CFF2")
        return nil unless cff2

        # Get CharString with blend operators
        # This is a placeholder - full implementation would parse CharString
        # and extract blend operator data

        # Convert blend data to tuples
        # Placeholder for full implementation
        nil
      end

      # Check if variation data can be converted
      #
      # @return [Boolean] True if conversion possible
      def can_convert?
        !@axes.empty? && (
          has_variation_table?("gvar") ||
          has_variation_table?("CFF2")
        )
      end

      private

      # Convert tuple variations to blend format
      #
      # @param tuple_data [Hash] Tuple variation data from gvar
      # @return [Hash] Blend format data
      def convert_tuples_to_blend(tuple_data)
        tuples = tuple_data[:tuples] || []
        point_count = tuple_data[:point_count] || 0

        # Build blend regions from tuples
        regions = tuples.map { |tuple| build_region_from_tuple(tuple) }

        # Extract deltas for each point
        point_deltas = extract_point_deltas(tuples, point_count)

        {
          regions: regions,
          point_deltas: point_deltas,
          num_regions: regions.length,
          num_axes: @axes.length,
        }
      end

      # Build region from tuple peak/start/end coordinates
      #
      # @param tuple [Hash] Tuple data with :peak, :start, :end
      # @return [Hash] Region definition
      def build_region_from_tuple(tuple)
        region = {}

        @axes.each_with_index do |axis, axis_index|
          # Extract coordinates for this axis
          peak = tuple[:peak] ? tuple[:peak][axis_index] : 0.0
          start_val = tuple[:start] ? tuple[:start][axis_index] : -1.0
          end_val = tuple[:end] ? tuple[:end][axis_index] : 1.0

          region[axis.axis_tag] = {
            start: start_val,
            peak: peak,
            end: end_val,
          }
        end

        region
      end

      # Extract point deltas from all tuples
      #
      # @param tuples [Array<Hash>] Tuple variations
      # @param point_count [Integer] Number of points
      # @return [Array<Array<Hash>>] Deltas per point per tuple
      def extract_point_deltas(tuples, point_count)
        return [] if point_count.zero?

        # Initialize deltas array
        point_deltas = Array.new(point_count) { [] }

        # For each tuple, extract deltas for all points
        tuples.each do |tuple|
          deltas = parse_tuple_deltas(tuple, point_count)

          deltas.each_with_index do |delta, point_index|
            point_deltas[point_index] << delta
          end
        end

        point_deltas
      end

      # Parse deltas from a tuple
      #
      # @param tuple [Hash] Tuple data
      # @param point_count [Integer] Number of points
      # @return [Array<Hash>] Deltas with :x and :y
      def parse_tuple_deltas(_tuple, point_count)
        # This is a placeholder - full implementation would:
        # 1. Parse delta data from tuple
        # 2. Decompress if needed
        # 3. Return array of { x: dx, y: dy } for each point

        Array.new(point_count) { { x: 0, y: 0 } }
      end

      # Convert blend data to tuple format
      #
      # @param blend_data [Hash] Blend format data
      # @return [Hash] Tuple variation data
      def convert_blend_to_tuples(blend_data)
        regions = blend_data[:regions] || []
        point_deltas = blend_data[:point_deltas] || []

        # Build tuples from regions
        tuples = regions.map.with_index do |region, region_index|
          build_tuple_from_region(region, point_deltas, region_index)
        end

        {
          tuples: tuples,
          point_count: point_deltas.length,
        }
      end

      # Build tuple from region and deltas
      #
      # @param region [Hash] Region definition
      # @param point_deltas [Array<Array<Hash>>] Deltas per point
      # @param region_index [Integer] Region index
      # @return [Hash] Tuple data
      def build_tuple_from_region(region, point_deltas, region_index)
        # Extract peak, start, end for all axes
        peak = Array.new(@axes.length, 0.0)
        start_vals = Array.new(@axes.length, -1.0)
        end_vals = Array.new(@axes.length, 1.0)

        @axes.each_with_index do |axis, axis_index|
          axis_region = region[axis.axis_tag]
          next unless axis_region

          peak[axis_index] = axis_region[:peak]
          start_vals[axis_index] = axis_region[:start]
          end_vals[axis_index] = axis_region[:end]
        end

        # Extract deltas for this region
        deltas = point_deltas.map do |point_delta_set|
          point_delta_set[region_index] || { x: 0, y: 0 }
        end

        {
          peak: peak,
          start: start_vals,
          end: end_vals,
          deltas: deltas,
        }
      end

      # Encode deltas in CharString blend format
      #
      # @param base_value [Numeric] Base value
      # @param deltas [Array<Numeric>] Delta values
      # @return [Array<Numeric>] Blend operator arguments
      def encode_blend_operator(base_value, deltas)
        # CFF2 blend format: base_value delta1 delta2 ... K N blend
        # Where K = number of deltas, N = number of blend operations
        [base_value] + deltas + [deltas.length, 1]
      end

      # Decode blend operator arguments to base and deltas
      #
      # @param args [Array<Numeric>] Blend operator arguments
      # @return [Hash] Base value and deltas
      def decode_blend_operator(args)
        return { base: 0, deltas: [] } if args.length < 3

        # Last two values are K and N
        k = args[-2]
        _n = args[-1]

        # Before K and N: base + deltas
        values = args[0...-2]
        base = values[0] || 0
        deltas = values[1, k] || []

        { base: base, deltas: deltas }
      end
    end
  end
end
