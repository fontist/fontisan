# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Blend operator handler for CFF2 CharStrings
      #
      # The blend operator is the key mechanism for applying variations in CFF2.
      # It takes base values and deltas, and applies them based on variation
      # coordinates to produce blended values.
      #
      # Blend Operator Format:
      #   Stack: base1 Δ1_axis1 ... Δ1_axisN base2 Δ2_axis1 ... Δ2_axisN ... K N
      #
      # Where:
      #   - base_i = base value for the i-th operand
      #   - Δi_axisj = delta for i-th operand on j-th axis
      #   - K = number of operands to blend (integer)
      #   - N = number of variation axes (integer)
      #
      # Result:
      #   Produces K blended values on the stack
      #
      # Blending Formula:
      #   blended_value = base + Σ(delta[i] * scalar[i])
      #
      # Where scalar[i] is computed from the current design space coordinates
      # for axis i.
      #
      # Reference: Adobe Technical Note #5177
      #
      # @example Applying blend with coordinates
      #   blend = BlendOperator.new(num_axes: 2)
      #   data = {
      #     num_values: 2,
      #     num_axes: 2,
      #     blends: [
      #       { base: 100, deltas: [10, 5] },
      #       { base: 200, deltas: [20, 10] }
      #     ]
      #   }
      #   scalars = [0.5, 0.3]  # From coordinate interpolation
      #   result = blend.apply(data, scalars)
      #   # => [105.0, 216.0]  # 100 + (10*0.5 + 5*0.3), 200 + (20*0.5 + 10*0.3)
      class BlendOperator
        # @return [Integer] Number of variation axes
        attr_reader :num_axes

        # Initialize blend operator handler
        #
        # @param num_axes [Integer] Number of variation axes
        def initialize(num_axes:)
          @num_axes = num_axes
        end

        # Parse blend operands from stack
        #
        # Extracts blend data from a flattened array of operands.
        #
        # @param operands [Array<Numeric>] Stack operands (including K and N)
        # @return [Hash, nil] Parsed blend data or nil if invalid
        def parse(operands)
          return nil if operands.size < 2

          # Last two values are K and N
          n = operands[-1].to_i
          k = operands[-2].to_i

          # Validate number of axes matches
          if n != @num_axes
            warn "Blend operator axes mismatch: expected #{@num_axes}, got #{n}"
            return nil
          end

          # Validate we have enough operands: K * (N + 1) + 2
          required_total = k * (n + 1) + 2
          if operands.size < required_total
            warn "Blend requires #{required_total} operands, got #{operands.size}"
            return nil
          end

          # Extract blend operands (everything except K and N)
          blend_operands = operands[-required_total..-3]

          # Parse into base + deltas structure
          blends = []
          k.times do |i|
            offset = i * (n + 1)
            base = blend_operands[offset]
            deltas = blend_operands[offset + 1, n] || []

            blends << {
              base: base,
              deltas: deltas,
            }
          end

          {
            num_values: k,
            num_axes: n,
            blends: blends,
          }
        end

        # Apply blend operation with variation scalars
        #
        # Computes blended values from base values and deltas using the
        # provided scalars (one per axis).
        #
        # @param blend_data [Hash] Parsed blend data from parse()
        # @param scalars [Array<Float>] Variation scalars (one per axis)
        # @return [Array<Float>] Blended values
        def apply(blend_data, scalars)
          return [] if blend_data.nil?

          # Ensure we have scalars for all axes
          scalars = Array(scalars)
          if scalars.size < blend_data[:num_axes]
            # Pad with zeros if not enough scalars
            scalars = scalars + ([0.0] * (blend_data[:num_axes] - scalars.size))
          end

          # Apply blend to each value
          blend_data[:blends].map do |blend|
            apply_single_blend(blend, scalars)
          end
        end

        # Apply blend to a single value
        #
        # @param blend [Hash] Single blend entry with :base and :deltas
        # @param scalars [Array<Float>] Variation scalars
        # @return [Float] Blended value
        def apply_single_blend(blend, scalars)
          base = blend[:base].to_f
          deltas = blend[:deltas]

          # Apply formula: result = base + Σ(delta[i] * scalar[i])
          result = base
          deltas.each_with_index do |delta, axis_index|
            scalar = scalars[axis_index] || 0.0
            result += delta.to_f * scalar
          end

          result
        end

        # Calculate variation scalars from coordinates
        #
        # This converts normalized coordinates [-1, 1] to scalars for each axis.
        # For now, this is a simple pass-through, but will integrate with the
        # interpolator in Phase B.
        #
        # @param coordinates [Hash<String, Float>] Axis coordinates
        # @param axes [Array<VariationAxisRecord>] Variation axes from fvar
        # @return [Array<Float>] Scalars for each axis
        def calculate_scalars(coordinates, axes)
          return [] if axes.nil? || axes.empty?

          axes.map do |axis|
            coord = coordinates[axis.axis_tag] || axis.default_value
            normalize_coordinate(coord, axis)
          end
        end

        # Normalize a coordinate value to [-1, 1] range
        #
        # @param value [Float] Coordinate value
        # @param axis [VariationAxisRecord] Axis definition
        # @return [Float] Normalized coordinate in [-1, 1]
        def normalize_coordinate(value, axis)
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

        # Validate blend data structure
        #
        # @param blend_data [Hash] Blend data to validate
        # @return [Boolean] True if valid
        def valid?(blend_data)
          return false if blend_data.nil?
          return false unless blend_data.is_a?(Hash)
          return false unless blend_data.key?(:num_values)
          return false unless blend_data.key?(:num_axes)
          return false unless blend_data.key?(:blends)
          return false unless blend_data[:num_values].is_a?(Integer)
          return false unless blend_data[:num_axes].is_a?(Integer)
          return false unless blend_data[:blends].is_a?(Array)
          return false if blend_data[:blends].size != blend_data[:num_values]

          # Validate each blend entry
          blend_data[:blends].all? do |blend|
            blend.is_a?(Hash) &&
              blend.key?(:base) &&
              blend.key?(:deltas) &&
              blend[:deltas].is_a?(Array) &&
              blend[:deltas].size == blend_data[:num_axes]
          end
        end

        # Get number of operands required for blend
        #
        # @param k [Integer] Number of values to blend
        # @param n [Integer] Number of axes
        # @return [Integer] Total operands required (including K and N)
        def self.operand_count(k, n)
          k * (n + 1) + 2
        end

        # Check if enough operands are available
        #
        # @param stack_size [Integer] Current stack size
        # @param k [Integer] Number of values to blend
        # @param n [Integer] Number of axes
        # @return [Boolean] True if enough operands
        def self.sufficient_operands?(stack_size, k, n)
          stack_size >= operand_count(k, n)
        end
      end
    end
  end
end
