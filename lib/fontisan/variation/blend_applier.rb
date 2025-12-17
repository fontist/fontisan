# frozen_string_literal: true

require_relative "interpolator"

module Fontisan
  module Variation
    # Applies CFF2 blend operators during CharString execution
    #
    # The blend operator in CFF2 CharStrings provides variation support by
    # blending base values with deltas based on design space coordinates.
    #
    # Blend Format:
    #   v1 Δv1_axis1 Δv1_axis2 ... v2 Δv2_axis1 ... K N blend
    #
    # Where:
    # - K = number of values to blend
    # - N = number of axes
    # - Each value has N deltas (one per axis)
    #
    # The applier calculates blended values:
    #   result = base + Σ(delta_i × scalar_i)
    #
    # Reference: Adobe Technical Note #5177 (CFF2 specification)
    #
    # @example Applying blend operators
    #   applier = Fontisan::Variation::BlendApplier.new(interpolator)
    #   blended = applier.apply_blend(base: 100, deltas: [10, 5], scalars: [0.8, 0.5])
    #   # => 110.5 (100 + 10*0.8 + 5*0.5)
    class BlendApplier
      # @return [Interpolator] Coordinate interpolator
      attr_reader :interpolator

      # @return [Array<Float>] Current variation scalars
      attr_reader :scalars

      # Initialize blend applier
      #
      # @param interpolator [Interpolator] Coordinate interpolator
      # @param coordinates [Hash<String, Float>] Design space coordinates
      def initialize(interpolator, coordinates = {})
        @interpolator = interpolator
        @coordinates = coordinates
        @scalars = []
      end

      # Set design space coordinates
      #
      # Updates the variation scalars based on new coordinates.
      #
      # @param coordinates [Hash<String, Float>] Axis tag => value
      # @param axes [Array] Variation axes from fvar
      def set_coordinates(coordinates, axes)
        @coordinates = coordinates
        @scalars = calculate_scalars(axes)
      end

      # Apply blend operation
      #
      # Blends base value with deltas using variation scalars.
      #
      # @param base [Numeric] Base value
      # @param deltas [Array<Numeric>] Delta values (one per axis)
      # @param num_axes [Integer] Number of axes (for validation)
      # @return [Float] Blended value
      # @raise [InvalidVariationDataError] If delta count doesn't match axis count
      def apply_blend(base:, deltas:, num_axes: nil)
        # Validate delta count matches axes
        if num_axes && deltas.length != num_axes
          raise InvalidVariationDataError.new(
            message: "Blend delta count (#{deltas.length}) doesn't match axes (#{num_axes})",
            details: {
              delta_count: deltas.length,
              expected_axes: num_axes,
              base_value: base,
            },
          )
        end

        # Start with base value
        result = base.to_f

        # Apply each delta with its scalar
        deltas.each_with_index do |delta, index|
          scalar = @scalars[index] || 0.0
          result += delta.to_f * scalar
        end

        result
      end

      # Apply multiple blend operations
      #
      # Processes multiple values with their deltas.
      #
      # @param blends [Array<Hash>] Array of { base:, deltas: } hashes
      # @param num_axes [Integer] Number of axes
      # @return [Array<Float>] Blended values
      def apply_blends(blends, num_axes)
        blends.map do |blend|
          apply_blend(
            base: blend[:base],
            deltas: blend[:deltas],
            num_axes: num_axes,
          )
        end
      end

      # Apply blend operator from CharString stack
      #
      # Processes blend operator arguments from CharString execution.
      #
      # @param operands [Array<Numeric>] Blend operands from stack
      # @param num_values [Integer] K (number of values to blend)
      # @param num_axes [Integer] N (number of axes)
      # @return [Array<Float>] Blended values
      # @raise [InvalidVariationDataError] If operand count doesn't match expected format
      def apply_blend_operands(operands, num_values, num_axes)
        # Expected operands: K * (N + 1)
        expected_count = num_values * (num_axes + 1)

        if operands.length != expected_count
          raise InvalidVariationDataError.new(
            message: "Blend operand count mismatch: expected #{expected_count}, got #{operands.length}",
            details: {
              operand_count: operands.length,
              expected_count: expected_count,
              num_values: num_values,
              num_axes: num_axes,
            },
          )
        end

        blended_values = []

        num_values.times do |i|
          offset = i * (num_axes + 1)
          base = operands[offset]
          deltas = operands[offset + 1, num_axes] || []

          blended_values << apply_blend(
            base: base,
            deltas: deltas,
            num_axes: num_axes,
          )
        end

        blended_values
      end

      # Calculate scalars for current coordinates
      #
      # Converts design space coordinates to normalized scalars [-1, 1].
      #
      # @param axes [Array] Variation axes
      # @return [Array<Float>] Scalar for each axis
      def calculate_scalars(axes)
        axes.map do |axis|
          coord = @coordinates[axis.axis_tag] || axis.default_value
          @interpolator.normalize_coordinate(coord, axis.axis_tag)
        end
      end

      # Check if coordinates are at default
      #
      # @return [Boolean] True if all scalars are zero
      def at_default?
        @scalars.all?(&:zero?)
      end

      # Get blended point coordinates
      #
      # Applies blend to X and Y coordinates simultaneously.
      #
      # @param base_x [Numeric] Base X coordinate
      # @param base_y [Numeric] Base Y coordinate
      # @param deltas_x [Array<Numeric>] X deltas
      # @param deltas_y [Array<Numeric>] Y deltas
      # @return [Array<Float>] [blended_x, blended_y]
      def blend_point(base_x, base_y, deltas_x, deltas_y)
        [
          apply_blend(base: base_x, deltas: deltas_x),
          apply_blend(base: base_y, deltas: deltas_y),
        ]
      end

      # Convert blend data to static values
      #
      # For instance generation, replaces blend operators with static values.
      #
      # @param blend_data [Array<Hash>] Blend operations data
      # @return [Array<Float>] Static blended values
      def blend_to_static(blend_data)
        blend_data.flat_map do |blend_op|
          apply_blends(blend_op[:blends], blend_op[:num_axes])
        end
      end
    end
  end
end
