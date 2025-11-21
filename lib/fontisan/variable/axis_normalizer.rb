# frozen_string_literal: true

require "yaml"

module Fontisan
  module Variable
    # Normalizes user coordinates to design space
    #
    # Converts user-provided axis coordinates (e.g., wght=700) to normalized
    # values in the range -1.0 to 1.0 based on axis definitions from the fvar table.
    #
    # The normalization algorithm follows the OpenType specification:
    # - For values below default: normalized = (value - default) / (default - min)
    # - For values above default: normalized = (value - default) / (max - default)
    # - Values are clamped to the -1.0 to 1.0 range
    #
    # @example Normalize coordinates
    #   normalizer = AxisNormalizer.new(fvar_table)
    #   normalized = normalizer.normalize({ "wght" => 700, "wdth" => 100 })
    #   # => { "wght" => 0.5, "wdth" => 0.0 }
    class AxisNormalizer
      # @return [Hash] Configuration settings
      attr_reader :config

      # @return [Hash] Axis definitions from fvar table
      attr_reader :axes

      # Initialize the normalizer
      #
      # @param fvar [Fontisan::Tables::Fvar] Font variations table
      # @param config [Hash] Optional configuration overrides
      def initialize(fvar, config = {})
        @fvar = fvar
        @config = load_config.merge(config)
        @axes = build_axis_map
      end

      # Normalize user coordinates to design space
      #
      # @param user_coords [Hash<String, Numeric>] User coordinates by axis tag
      # @return [Hash<String, Float>] Normalized coordinates (-1.0 to 1.0)
      def normalize(user_coords)
        result = {}

        @axes.each do |tag, axis_info|
          user_value = user_coords[tag] || user_coords[tag.to_sym]

          # Use default if not provided and config allows
          if user_value.nil?
            user_value = if @config.dig(:coordinate_normalization,
                                        :use_axis_defaults)
                           axis_info[:default]
                         else
                           next
                         end
          end

          # Validate and clamp if configured
          validated_value = validate_coordinate(user_value, axis_info)

          # Normalize the value
          normalized = normalize_value(validated_value, axis_info)

          result[tag] = normalized
        end

        result
      end

      # Normalize a single axis value
      #
      # @param value [Numeric] User coordinate value
      # @param axis_tag [String] Axis tag
      # @return [Float] Normalized value (-1.0 to 1.0)
      def normalize_axis(value, axis_tag)
        axis_info = @axes[axis_tag]
        raise ArgumentError, "Unknown axis: #{axis_tag}" unless axis_info

        validated_value = validate_coordinate(value, axis_info)
        normalize_value(validated_value, axis_info)
      end

      # Get axis information
      #
      # @param axis_tag [String] Axis tag
      # @return [Hash, nil] Axis information or nil
      def axis_info(axis_tag)
        @axes[axis_tag]
      end

      # Get all axis tags
      #
      # @return [Array<String>] Array of axis tags
      def axis_tags
        @axes.keys
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
        # Return default config if file doesn't exist
        {
          coordinate_normalization: {
            normalize: true,
            use_axis_defaults: true,
            normalized_precision: 6,
          },
          delta_application: {
            validate_coordinates: true,
            clamp_coordinates: true,
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

      # Build axis information map from fvar table
      #
      # @return [Hash<String, Hash>] Map of axis tag to axis info
      def build_axis_map
        return {} unless @fvar

        @fvar.axes.each_with_object({}) do |axis, hash|
          # Convert BinData::String to regular Ruby String for proper Hash key behavior
          tag = axis.axis_tag.to_s
          hash[tag] = {
            min: axis.min_value,
            default: axis.default_value,
            max: axis.max_value,
            name_id: axis.axis_name_id,
          }
        end
      end

      # Validate and optionally clamp coordinate value
      #
      # @param value [Numeric] User coordinate value
      # @param axis_info [Hash] Axis information
      # @return [Float] Validated value
      def validate_coordinate(value, axis_info)
        value = value.to_f

        # Check if validation is enabled
        if @config.dig(:delta_application, :validate_coordinates)
          min = axis_info[:min]
          max = axis_info[:max]

          # Clamp if configured
          if @config.dig(:delta_application, :clamp_coordinates)
            value = [[value, min].max, max].min
          elsif value < min || value > max
            raise ArgumentError,
                  "Coordinate #{value} out of range [#{min}, #{max}]"
          end
        end

        value
      end

      # Normalize a value to -1.0 to 1.0 range
      #
      # @param value [Float] User coordinate value
      # @param axis_info [Hash] Axis information
      # @return [Float] Normalized value
      def normalize_value(value, axis_info)
        default = axis_info[:default]

        # Value at default is always 0.0
        return 0.0 if (value - default).abs < Float::EPSILON

        if value < default
          # Below default: negative range
          min = axis_info[:min]
          range = default - min

        else
          # Above default: positive range
          max = axis_info[:max]
          range = max - default

        end
        return 0.0 if range.abs < Float::EPSILON

        normalized = (value - default) / range

        # Clamp to -1.0 to 1.0
        normalized = [[-1.0, normalized].max, 1.0].min

        # Apply precision
        precision = @config.dig(:coordinate_normalization,
                                :normalized_precision) || 6
        normalized.round(precision)
      end
    end
  end
end
