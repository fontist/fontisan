# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Private DICT blend handler for CFF2
      #
      # Handles blend operators in Private DICT which allow hint parameters
      # to vary across the design space in variable fonts.
      #
      # Blend in Private DICT format:
      #   base_value delta1 delta2 ... deltaN num_axes blend
      #
      # Example for BlueValues with 2 axes:
      #   -10 2 1   0 1 0   500 10 5   510 12 6   2 blend
      #   This creates BlueValues that vary across the design space.
      #
      # Reference: Adobe Technical Note #5177 (CFF2)
      #
      # @example Parsing blend in Private DICT
      #   handler = PrivateDictBlendHandler.new(private_dict)
      #   blue_values = handler.parse_blend_array(:blue_values, num_axes: 2)
      class PrivateDictBlendHandler
        # @return [Hash] Private DICT data
        attr_reader :private_dict

        # Initialize handler with Private DICT data
        #
        # @param private_dict [Hash] Parsed Private DICT
        def initialize(private_dict)
          @private_dict = private_dict
        end

        # Check if Private DICT contains blend data
        #
        # @return [Boolean] True if blend operators are present
        def has_blend?
          # In a DICT with blend, values are arrays with blend data
          @private_dict.values.any? { |v| blend_value?(v) }
        end

        # Parse blended array (like BlueValues)
        #
        # @param key [Symbol, Integer] DICT operator key
        # @param num_axes [Integer] Number of variation axes
        # @return [Hash, nil] Parsed blend data or nil if not present
        def parse_blend_array(key, num_axes:)
          value = @private_dict[key]
          return nil unless value.is_a?(Array)

          # Check if this is blend data
          # Format: base1 delta1_1 ... delta1_N base2 delta2_1 ... delta2_N ...
          # The array must be divisible by (num_axes + 1)
          return nil unless value.size % (num_axes + 1) == 0

          num_values = value.size / (num_axes + 1)
          blends = []

          num_values.times do |i|
            offset = i * (num_axes + 1)
            base = value[offset]
            deltas = value[offset + 1, num_axes] || []

            blends << {
              base: base,
              deltas: deltas
            }
          end

          {
            num_values: num_values,
            num_axes: num_axes,
            blends: blends
          }
        end

        # Parse single blended value
        #
        # @param key [Symbol, Integer] DICT operator key
        # @param num_axes [Integer] Number of variation axes
        # @return [Hash, nil] Parsed blend data or nil if not present
        def parse_blend_value(key, num_axes:)
          value = @private_dict[key]
          return nil unless value.is_a?(Array)

          # Single value format: base delta1 delta2 ... deltaN
          expected_size = num_axes + 1
          return nil unless value.size == expected_size

          {
            base: value[0],
            deltas: value[1..num_axes],
            num_axes: num_axes
          }
        end

        # Apply blend at specific coordinates
        #
        # @param blend_data [Hash] Parsed blend data
        # @param scalars [Array<Float>] Region scalars for each axis
        # @return [Array<Float>, Float] Blended values
        def apply_blend(blend_data, scalars)
          return nil unless blend_data

          if blend_data.key?(:blends)
            # Array of blended values
            blend_data[:blends].map do |blend|
              apply_single_blend(blend, scalars)
            end
          else
            # Single blended value
            apply_single_blend(blend_data, scalars)
          end
        end

        # Apply blend to a single value
        #
        # @param blend [Hash] Single blend with :base and :deltas
        # @param scalars [Array<Float>] Region scalars
        # @return [Float] Blended value
        def apply_single_blend(blend, scalars)
          base = blend[:base].to_f
          deltas = blend[:deltas]

          # Apply formula: result = base + Σ(delta[i] * scalar[i])
          result = base
          deltas.each_with_index do |delta, i|
            scalar = scalars[i] || 0.0
            result += delta.to_f * scalar
          end

          result
        end

        # Get blended Private DICT values at coordinates
        #
        # @param num_axes [Integer] Number of variation axes
        # @param scalars [Array<Float>] Region scalars
        # @return [Hash] Private DICT with blended values
        def blended_dict(num_axes:, scalars:)
          result = {}

          @private_dict.each do |key, value|
            if value.is_a?(Array) && blend_value?(value)
              # Try parsing as blend array
              blend_data = parse_blend_array(key, num_axes: num_axes)
              if blend_data
                result[key] = apply_blend(blend_data, scalars)
              else
                # Try as single blend value
                blend_data = parse_blend_value(key, num_axes: num_axes)
                result[key] = blend_data ? apply_blend(blend_data, scalars) : value
              end
            else
              # Non-blend value, copy as-is
              result[key] = value
            end
          end

          result
        end

        # Check if value looks like blend data
        #
        # @param value [Object] Value to check
        # @return [Boolean] True if value could be blend data
        def blend_value?(value)
          # Blend values are arrays with multiple elements
          value.is_a?(Array) && value.size > 1
        end

        # Rebuild Private DICT with hints injected
        #
        # This method prepares Private DICT for rebuilding, preserving
        # blend operators while incorporating new hint values.
        #
        # @param hints [Hash] Hint values to inject
        # @param num_axes [Integer] Number of variation axes
        # @return [Hash] Modified Private DICT
        def rebuild_with_hints(hints, num_axes:)
          result = @private_dict.dup

          # Inject hint values
          hints.each do |key, value|
            if value.is_a?(Hash) && (value.key?(:base) || value.key?("base")) && (value.key?(:deltas) || value.key?("deltas"))
              # Hint with blend data - normalize and flatten for DICT storage
              normalized_value = {
                base: value[:base] || value["base"],
                deltas: value[:deltas] || value["deltas"]
              }
              result[key] = flatten_blend(normalized_value, num_axes: num_axes)
            else
              # Simple hint value
              result[key] = value
            end
          end

          result
        end

        # Flatten blend data to array format
        #
        # @param blend_data [Hash] Blend data with :base and :deltas
        # @param num_axes [Integer] Number of variation axes
        # @return [Array] Flattened array
        def flatten_blend(blend_data, num_axes:)
          if blend_data.key?(:blends)
            # Array of blends
            blend_data[:blends].flat_map do |blend|
              [blend[:base]] + blend[:deltas]
            end
          else
            # Single blend
            [blend_data[:base]] + blend_data[:deltas]
          end
        end

        # Validate blend data structure
        #
        # @param num_axes [Integer] Expected number of axes
        # @return [Array<String>] Validation errors (empty if valid)
        def validate(num_axes:)
          errors = []

          @private_dict.each do |key, value|
            next unless value.is_a?(Array)
            next unless blend_value?(value)

            # Try parsing as blend array
            blend_data = parse_blend_array(key, num_axes: num_axes)
            unless blend_data
              # Try as single blend value
              blend_data = parse_blend_value(key, num_axes: num_axes)
              unless blend_data
                errors << "Key #{key} has array value that doesn't match " \
                          "blend format for #{num_axes} axes"
              end
            end
          end

          errors
        end
      end
    end
  end
end