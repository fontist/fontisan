# frozen_string_literal: true

require "yaml"

module Fontisan
  module Variable
    # Applies metric deltas from HVAR, VVAR, and MVAR tables
    #
    # Processes variation data for font metrics including:
    # - Horizontal metrics (advance widths, LSB, RSB) via HVAR
    # - Vertical metrics (advance heights, TSB, BSB) via VVAR
    # - Font-level metrics (ascent, descent, line gap, etc.) via MVAR
    #
    # Uses ItemVariationStore and region scalars to calculate accumulated
    # deltas which are then applied to original metric values.
    #
    # @example Apply metric deltas
    #   processor = MetricDeltaProcessor.new(hvar, vvar, mvar)
    #   deltas = processor.apply_deltas(glyph_id, region_scalars)
    #   # => { advance_width: 10, lsb: -2, ... }
    class MetricDeltaProcessor
      # @return [Hash] Configuration settings
      attr_reader :config

      # Initialize the processor
      #
      # @param hvar [Fontisan::Tables::Hvar, nil] Horizontal variations table
      # @param vvar [Fontisan::Tables::Vvar, nil] Vertical variations table
      # @param mvar [Fontisan::Tables::Mvar, nil] Metrics variations table
      # @param config [Hash] Optional configuration overrides
      def initialize(hvar: nil, vvar: nil, mvar: nil, config: {})
        @hvar = hvar
        @vvar = vvar
        @mvar = mvar
        @config = load_config.merge(config)
      end

      # Apply all metric deltas for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Scalar for each region
      # @return [Hash] Metric deltas
      def apply_deltas(glyph_id, region_scalars)
        result = {}

        # Apply horizontal metric deltas if HVAR present
        if @hvar && @config.dig(:metric_deltas, :apply_hvar)
          result[:horizontal] = apply_hvar_deltas(glyph_id, region_scalars)
        end

        # Apply vertical metric deltas if VVAR present
        if @vvar && @config.dig(:metric_deltas, :apply_vvar)
          result[:vertical] = apply_vvar_deltas(glyph_id, region_scalars)
        end

        result
      end

      # Apply font-level metric deltas
      #
      # @param region_scalars [Array<Float>] Scalar for each region
      # @return [Hash] Font-level metric deltas
      def apply_font_metrics(region_scalars)
        return {} unless @mvar && @config.dig(:metric_deltas, :apply_mvar)

        result = {}

        # Process each metric tag in MVAR
        @mvar.metric_tags.each do |tag|
          delta_set = @mvar.metric_delta_set(tag)
          next unless delta_set

          # Calculate accumulated delta
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[tag] = apply_rounding(accumulated)
        end

        result
      end

      # Get advance width delta for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Integer] Advance width delta
      def advance_width_delta(glyph_id, region_scalars)
        return 0 unless @hvar

        delta_set = @hvar.advance_width_delta_set(glyph_id)
        return 0 unless delta_set

        accumulated = calculate_accumulated_delta(delta_set, region_scalars)
        apply_rounding(accumulated)
      end

      # Get LSB delta for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Integer] LSB delta
      def lsb_delta(glyph_id, region_scalars)
        return 0 unless @hvar

        delta_set = @hvar.lsb_delta_set(glyph_id)
        return 0 unless delta_set

        accumulated = calculate_accumulated_delta(delta_set, region_scalars)
        apply_rounding(accumulated)
      end

      # Get RSB delta for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Integer] RSB delta
      def rsb_delta(glyph_id, region_scalars)
        return 0 unless @hvar

        delta_set = @hvar.rsb_delta_set(glyph_id)
        return 0 unless delta_set

        accumulated = calculate_accumulated_delta(delta_set, region_scalars)
        apply_rounding(accumulated)
      end

      # Check if horizontal variations are present
      #
      # @return [Boolean] True if HVAR present
      def has_hvar?
        !@hvar.nil?
      end

      # Check if vertical variations are present
      #
      # @return [Boolean] True if VVAR present
      def has_vvar?
        !@vvar.nil?
      end

      # Check if font metric variations are present
      #
      # @return [Boolean] True if MVAR present
      def has_mvar?
        !@mvar.nil?
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
          metric_deltas: {
            apply_hvar: true,
            apply_vvar: true,
            apply_mvar: true,
            update_dependent_metrics: true,
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

      # Apply HVAR deltas for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Hash] Horizontal metric deltas
      def apply_hvar_deltas(glyph_id, region_scalars)
        result = {}

        # Advance width delta
        if (delta_set = @hvar.advance_width_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:advance_width] = apply_rounding(accumulated)
        end

        # LSB delta
        if (delta_set = @hvar.lsb_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:lsb] = apply_rounding(accumulated)
        end

        # RSB delta
        if (delta_set = @hvar.rsb_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:rsb] = apply_rounding(accumulated)
        end

        result
      end

      # Apply VVAR deltas for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param region_scalars [Array<Float>] Region scalars
      # @return [Hash] Vertical metric deltas
      def apply_vvar_deltas(glyph_id, region_scalars)
        result = {}

        # Similar to HVAR but for vertical metrics
        # VVAR has the same structure as HVAR
        if @vvar.respond_to?(:advance_height_delta_set) && (delta_set = @vvar.advance_height_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:advance_height] = apply_rounding(accumulated)
        end

        if @vvar.respond_to?(:tsb_delta_set) && (delta_set = @vvar.tsb_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:tsb] = apply_rounding(accumulated)
        end

        if @vvar.respond_to?(:bsb_delta_set) && (delta_set = @vvar.bsb_delta_set(glyph_id))
          accumulated = calculate_accumulated_delta(delta_set, region_scalars)
          result[:bsb] = apply_rounding(accumulated)
        end

        result
      end

      # Calculate accumulated delta from delta set and region scalars
      #
      # @param delta_set [Array<Integer>] Delta values for each region
      # @param region_scalars [Array<Float>] Scalar for each region
      # @return [Float] Accumulated delta
      def calculate_accumulated_delta(delta_set, region_scalars)
        accumulated = 0.0

        delta_set.each_with_index do |delta, index|
          next if index >= region_scalars.length

          scalar = region_scalars[index]
          accumulated += delta * scalar
        end

        accumulated
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
    end
  end
end
