# frozen_string_literal: true

module Fontisan
  module Variation
    # Coordinate interpolator for variable fonts
    #
    # This class interpolates values in the variation design space by
    # calculating scalars based on the current coordinates and variation
    # regions/tuples.
    #
    # Interpolation Process:
    # 1. Normalize user coordinates to [-1, 1] range based on axis min/default/max
    # 2. For each variation region, calculate a scalar that represents how much
    #    that region contributes at the current coordinates
    # 3. Apply the scalars to deltas to get the final interpolated value
    #
    # Region Scalar Calculation:
    # For each axis, given a region [start, peak, end] and coordinate c:
    # - If c < start or c > end: scalar = 0 (outside region)
    # - If c in [start, peak]: scalar = (c - start) / (peak - start)
    # - If c in [peak, end]: scalar = (end - c) / (end - peak)
    # - If c == peak: scalar = 1 (at peak)
    #
    # For multi-axis regions, multiply the per-axis scalars together.
    #
    # Reference: OpenType Font Variations specification
    #
    # @example Interpolating a coordinate
    #   interpolator = Interpolator.new(axes)
    #   scalar = interpolator.calculate_scalar(
    #     coordinates: { "wght" => 600.0 },
    #     region: { "wght" => { start: 400, peak: 700, end: 900 } }
    #   )
    #   # => 0.666... (normalized position between 400 and 700)
    class Interpolator
      # @return [Array<VariationAxisRecord>] Variation axes
      attr_reader :axes

      # Initialize interpolator
      #
      # @param axes [Array<VariationAxisRecord>] Variation axes from fvar table
      def initialize(axes)
        @axes = axes || []
      end

      # Normalize a coordinate value to [-1, 1] range
      #
      # @param value [Float] User-space coordinate value
      # @param axis_tag [String] Axis tag (e.g., "wght", "wdth")
      # @return [Float] Normalized coordinate in [-1, 1]
      def normalize_coordinate(value, axis_tag)
        axis = find_axis(axis_tag)
        return 0.0 unless axis

        # Clamp to axis range
        value = [[value, axis.min_value].max, axis.max_value].min

        # Normalize to [-1, 1]
        if value < axis.default_value
          # Normalize between min and default (maps to -1..0)
          range = axis.default_value - axis.min_value
          return -1.0 if range.zero?

          (value - axis.default_value) / range
        elsif value > axis.default_value
          # Normalize between default and max (maps to 0..1)
          range = axis.max_value - axis.default_value
          return 1.0 if range.zero?

          (value - axis.default_value) / range
        else
          # At default value
          0.0
        end
      end

      # Normalize all coordinates
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @return [Hash<String, Float>] Normalized coordinates
      def normalize_coordinates(coordinates)
        result = {}
        @axes.each do |axis|
          tag = axis.axis_tag
          value = coordinates[tag] || axis.default_value
          result[tag] = normalize_coordinate(value, tag)
        end
        result
      end

      # Calculate scalar for a single axis region
      #
      # @param coord [Float] Normalized coordinate value [-1, 1]
      # @param region [Hash] Region definition with :start, :peak, :end
      # @return [Float] Scalar value [0, 1]
      def calculate_axis_scalar(coord, region)
        start_val = region[:start] || -1.0
        peak = region[:peak] || 0.0
        end_val = region[:end] || 1.0

        # Outside region
        return 0.0 if coord < start_val || coord > end_val

        # At or beyond peak
        return 1.0 if coord == peak

        # Between start and peak
        if coord < peak
          range = peak - start_val
          return 1.0 if range.zero?

          (coord - start_val) / range
        else
          # Between peak and end
          range = end_val - peak
          return 1.0 if range.zero?

          (end_val - coord) / range
        end
      end

      # Calculate scalar for a multi-axis region
      #
      # For multi-axis regions, the final scalar is the product of per-axis scalars.
      #
      # @param coordinates [Hash<String, Float>] Normalized coordinates
      # @param region [Hash<String, Hash>] Region definition per axis
      # @return [Float] Combined scalar [0, 1]
      def calculate_region_scalar(coordinates, region)
        scalar = 1.0

        region.each do |axis_tag, axis_region|
          coord = coordinates[axis_tag] || 0.0
          axis_scalar = calculate_axis_scalar(coord, axis_region)

          # If any axis has zero scalar, entire region has zero contribution
          return 0.0 if axis_scalar.zero?

          scalar *= axis_scalar
        end

        scalar
      end

      # Calculate scalars for all regions
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param regions [Array<Hash>] Array of region definitions
      # @return [Array<Float>] Scalars for each region
      def calculate_scalars(coordinates, regions)
        # Normalize coordinates first
        normalized = normalize_coordinates(coordinates)

        # Calculate scalar for each region
        regions.map do |region|
          calculate_region_scalar(normalized, region)
        end
      end

      # Interpolate a value using deltas
      #
      # @param base_value [Numeric] Base value
      # @param deltas [Array<Numeric>] Delta values (one per region)
      # @param scalars [Array<Float>] Region scalars (one per region)
      # @return [Float] Interpolated value
      def interpolate_value(base_value, deltas, scalars)
        result = base_value.to_f

        deltas.each_with_index do |delta, index|
          scalar = scalars[index] || 0.0
          result += delta.to_f * scalar
        end

        result
      end

      # Interpolate a point (x, y coordinates)
      #
      # @param base_point [Hash] Base point with :x and :y
      # @param delta_points [Array<Hash>] Delta points (one per region)
      # @param scalars [Array<Float>] Region scalars
      # @return [Hash] Interpolated point with :x and :y
      def interpolate_point(base_point, delta_points, scalars)
        x = base_point[:x].to_f
        y = base_point[:y].to_f

        delta_points.each_with_index do |delta_point, index|
          scalar = scalars[index] || 0.0
          x += delta_point[:x].to_f * scalar
          y += delta_point[:y].to_f * scalar
        end

        { x: x, y: y }
      end

      # Build region from tuple variation data
      #
      # Converts gvar tuple data to the region format used by interpolator
      #
      # @param tuple [Hash] Tuple variation data with :peak, :start, :end
      # @return [Hash<String, Hash>] Region definition per axis
      def build_region_from_tuple(tuple)
        region = {}

        @axes.each_with_index do |axis, axis_index|
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

      private

      # Find axis by tag
      #
      # @param axis_tag [String] Axis tag
      # @return [VariationAxisRecord, nil] Axis or nil
      def find_axis(axis_tag)
        @axes.find { |axis| axis.axis_tag == axis_tag }
      end
    end
  end
end
