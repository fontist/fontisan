# frozen_string_literal: true

require "yaml"

module Fontisan
  module Variable
    # Calculates region scalars for variation regions
    #
    # Given normalized coordinates and variation regions, computes scalar values
    # (0.0 to 1.0) that determine how much each region contributes to the final
    # delta values. The algorithm follows the OpenType specification for region
    # matching.
    #
    # A region is defined by start, peak, and end coordinates for each axis:
    # - If coordinate is outside [start, end], scalar is 0.0
    # - If coordinate is at peak, scalar contribution for that axis is 1.0
    # - Otherwise, scalar is linearly interpolated
    # - Final scalar is the product of all axis contributions
    #
    # @example Calculate region scalars
    #   matcher = RegionMatcher.new(variation_region_list)
    #   scalars = matcher.match({ "wght" => 0.5 })
    #   # => [0.5, 1.0, 0.0, ...]
    class RegionMatcher
      # @return [Hash] Configuration settings
      attr_reader :config

      # @return [Array<Array<Hash>>] Variation regions
      attr_reader :regions

      # Initialize the region matcher
      #
      # @param variation_region_list [VariationCommon::VariationRegionList] Region list
      # @param axis_tags [Array<String>] Axis tags in order
      # @param config [Hash] Optional configuration overrides
      def initialize(variation_region_list, axis_tags, config = {})
        @variation_region_list = variation_region_list
        @axis_tags = axis_tags
        @config = load_config.merge(config)
        @regions = build_regions
        @scalar_cache = {} if @config.dig(:region_matching, :cache_scalars)
      end

      # Calculate scalars for all regions
      #
      # @param normalized_coords [Hash<String, Float>] Normalized coordinates
      # @return [Array<Float>] Scalar for each region (0.0 to 1.0)
      def match(normalized_coords)
        # Check cache if enabled
        if @config.dig(:region_matching, :cache_scalars)
          cache_key = cache_key_for(normalized_coords)
          return @scalar_cache[cache_key] if @scalar_cache.key?(cache_key)
        end

        scalars = @regions.map do |region|
          calculate_region_scalar(region, normalized_coords)
        end

        # Cache result if enabled
        if @config.dig(:region_matching, :cache_scalars)
          @scalar_cache[cache_key_for(normalized_coords)] = scalars
        end

        scalars
      end

      # Calculate scalar for a specific region
      #
      # @param region_index [Integer] Region index
      # @param normalized_coords [Hash<String, Float>] Normalized coordinates
      # @return [Float] Region scalar (0.0 to 1.0)
      def match_region(region_index, normalized_coords)
        return 0.0 if region_index >= @regions.length

        region = @regions[region_index]
        calculate_region_scalar(region, normalized_coords)
      end

      # Get number of regions
      #
      # @return [Integer] Region count
      def region_count
        @regions.length
      end

      # Clear scalar cache
      def clear_cache
        @scalar_cache&.clear
      end

      private

      # Load configuration from YAML file
      #
      # @return [Hash] Configuration hash
      def load_config
        config_path = File.join(__dir__, "..", "config",
                                "variable_settings.yml")
        YAML.load_file(config_path)
      rescue StandardError
        # Return default config
        {
          region_matching: {
            algorithm: "standard",
            multi_axis: true,
            cache_scalars: true,
          },
          delta_application: {
            min_scalar_threshold: 0.0001,
          },
        }
      end

      # Build region information from variation region list
      #
      # @return [Array<Array<Hash>>] Array of regions with axis coordinates
      def build_regions
        return [] unless @variation_region_list

        @variation_region_list.regions.map do |region_coords|
          # Map axis coordinates to hash
          region_coords.each_with_index.map do |coord, axis_index|
            {
              axis_tag: @axis_tags[axis_index],
              start: coord.start,
              peak: coord.peak,
              end: coord.end_value,
            }
          end
        end
      end

      # Calculate scalar for a region
      #
      # @param region [Array<Hash>] Region axis coordinates
      # @param normalized_coords [Hash<String, Float>] Normalized coordinates
      # @return [Float] Region scalar (0.0 to 1.0)
      def calculate_region_scalar(region, normalized_coords)
        # Start with scalar of 1.0
        scalar = 1.0

        # Process each axis in the region
        region.each do |axis_coord|
          axis_tag = axis_coord[:axis_tag]
          coord = normalized_coords[axis_tag] || normalized_coords[axis_tag.to_sym] || 0.0

          # Calculate contribution for this axis
          axis_scalar = calculate_axis_scalar(
            coord,
            axis_coord[:start],
            axis_coord[:peak],
            axis_coord[:end],
          )

          # Multiply into total scalar
          scalar *= axis_scalar

          # Early exit if scalar becomes 0
          break if scalar.zero?
        end

        # Apply minimum threshold if configured
        threshold = @config.dig(:delta_application,
                                :min_scalar_threshold) || 0.0
        scalar < threshold ? 0.0 : scalar
      end

      # Calculate scalar contribution for a single axis
      #
      # @param coord [Float] Normalized coordinate
      # @param start [Float] Region start
      # @param peak [Float] Region peak
      # @param end_coord [Float] Region end
      # @return [Float] Axis scalar (0.0 to 1.0)
      def calculate_axis_scalar(coord, start, peak, end_coord)
        # Outside region range: no contribution
        return 0.0 if coord < start || coord > end_coord

        # At peak: full contribution
        return 1.0 if (coord - peak).abs < Float::EPSILON

        # Between start and peak
        if coord < peak
          range = peak - start
          return 1.0 if range.abs < Float::EPSILON

          return (coord - start) / range
        end

        # Between peak and end
        range = end_coord - peak
        return 1.0 if range.abs < Float::EPSILON

        (end_coord - coord) / range
      end

      # Generate cache key for coordinates
      #
      # @param normalized_coords [Hash] Normalized coordinates
      # @return [String] Cache key
      def cache_key_for(normalized_coords)
        # Sort by axis tag for consistent keys
        sorted_coords = normalized_coords.sort_by { |tag, _| tag.to_s }
        sorted_coords.map { |tag, value| "#{tag}:#{value}" }.join("|")
      end
    end
  end
end
