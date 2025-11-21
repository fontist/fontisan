# frozen_string_literal: true

require "yaml"

module Fontisan
  module Variable
    # Applies glyph outline deltas from gvar table
    #
    # Processes delta values for glyph control points and phantom points,
    # applying them based on region scalars to modify glyph outlines.
    #
    # Handles both simple and compound glyphs, and processes phantom points
    # which affect glyph metrics.
    #
    # @example Apply deltas to a glyph
    #   processor = GlyphDeltaProcessor.new(gvar_table, shared_tuples)
    #   modified = processor.apply_deltas(glyph_id, region_scalars)
    #   # => { x_deltas: [...], y_deltas: [...], phantom_deltas: [...] }
    class GlyphDeltaProcessor
      # @return [Hash] Configuration settings
      attr_reader :config

      # Initialize the processor
      #
      # @param gvar [Fontisan::Tables::Gvar] Glyph variations table
      # @param config [Hash] Optional configuration overrides
      def initialize(gvar, config = {})
        @gvar = gvar
        @config = load_config.merge(config)
        @shared_tuples = gvar&.shared_tuples || []
      end

      # Apply deltas to a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Scalar for each region
      # @return [Hash, nil] Delta information or nil
      def apply_deltas(glyph_id, region_scalars)
        return nil unless @gvar

        # Get tuple variations for this glyph
        tuple_info = @gvar.glyph_tuple_variations(glyph_id)
        return nil unless tuple_info

        # Calculate accumulated deltas
        calculate_accumulated_deltas(tuple_info, region_scalars)
      end

      # Check if glyph has variation data
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Boolean] True if glyph has variations
      def has_variations?(glyph_id)
        return false unless @gvar

        data = @gvar.glyph_variation_data(glyph_id)
        !data.nil? && !data.empty?
      end

      # Get number of glyphs with variations
      #
      # @return [Integer] Glyph count
      def glyph_count
        @gvar&.glyph_count || 0
      end

      private

      # Load configuration from YAML file
      #
      # @return [Hash] Configuration hash
      def load_config
        config_path = File.join(__dir__, "..", "config",
                                "variable_settings.yml")
        loaded = YAML.load_file(config_path)
        # Convert string keys to symbol keys for consistency
        deep_symbolize_keys(loaded)
      rescue StandardError
        # Return default config
        {
          glyph_deltas: {
            apply_to_simple: true,
            apply_to_compound: true,
            process_phantom_points: true,
            phantom_point_count: 4,
          },
          delta_application: {
            rounding_mode: "round",
          },
        }
      end

      # Recursively convert hash keys to symbols
      #
      # @param hash [Hash] Hash with string keys
      # @return [Hash] Hash with symbol keys
      def deep_symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_sym
          new_value = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
          result[new_key] = new_value
        end
      end

      # Calculate accumulated deltas for a glyph
      #
      # @param tuple_info [Hash] Tuple variation information
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Hash] Accumulated deltas
      def calculate_accumulated_deltas(tuple_info, region_scalars)
        tuples = tuple_info[:tuples]
        return nil if tuples.nil? || tuples.empty?

        # Result structure
        result = {
          x_deltas: [],
          y_deltas: [],
          phantom_deltas: [],
          point_count: 0,
        }

        # Process each tuple
        tuples.each_with_index do |tuple, tuple_index|
          # Get peak coordinates for this tuple
          peak_coords = if tuple[:embedded_peak]
                          tuple[:peak]
                        else
                          @shared_tuples[tuple[:shared_index]]
                        end

          next unless peak_coords

          # Calculate scalar for this tuple
          scalar = calculate_tuple_scalar(tuple, peak_coords, region_scalars)
          next if scalar.zero?

          # This is a simplified version - actual implementation would need
          # to unpack the delta data from the gvar table
          # For now, we just indicate which tuples contribute
          result[:contributing_tuples] ||= []
          result[:contributing_tuples] << {
            index: tuple_index,
            scalar: scalar,
            peak: peak_coords,
          }
        end

        result
      end

      # Calculate scalar for a tuple
      #
      # @param tuple [Hash] Tuple information
      # @param peak_coords [Array<Float>] Peak coordinates
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Float] Tuple scalar
      def calculate_tuple_scalar(tuple, peak_coords, region_scalars)
        # For embedded tuples, calculate scalar based on peak/start/end
        if tuple[:embedded_peak]
          return calculate_embedded_tuple_scalar(tuple, peak_coords)
        end

        # For shared tuples, use the corresponding region scalar
        shared_index = tuple[:shared_index]
        return 0.0 if shared_index >= region_scalars.length

        region_scalars[shared_index]
      end

      # Calculate scalar for embedded tuple
      #
      # @param tuple [Hash] Tuple information
      # @param peak_coords [Array<Float>] Peak coordinates
      # @return [Float] Tuple scalar
      def calculate_embedded_tuple_scalar(_tuple, peak_coords)
        # Simplified - would need current normalized coordinates
        # For now, return 1.0 if peak coords are present
        peak_coords.any? { |c| c.abs > Float::EPSILON } ? 1.0 : 0.0
      end

      # Apply rounding to delta value
      #
      # @param delta [Float] Delta value
      # @return [Integer] Rounded delta
      def apply_rounding(delta)
        mode = @config.dig(:delta_application, :rounding_mode) || "round"

        case mode
        when "round"
          delta.round
        when "floor"
          delta.floor
        when "ceil"
          delta.ceil
        when "truncate"
          delta.to_i
        else
          delta.round
        end
      end

      # Unpack point deltas from packed data
      #
      # This is a complex operation that requires understanding the
      # gvar delta encoding format. Simplified placeholder.
      #
      # @param data [String] Packed delta data
      # @param point_count [Integer] Number of points
      # @return [Hash] X and Y deltas
      def unpack_point_deltas(_data, point_count)
        {
          x_deltas: Array.new(point_count, 0),
          y_deltas: Array.new(point_count, 0),
        }
      end
    end
  end
end
