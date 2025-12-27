# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Region matcher for calculating variation scalars
      #
      # Maps design space coordinates to region scalars based on
      # the Variable Store region definitions. Each region defines
      # a range (start, peak, end) for each variation axis.
      #
      # Scalar Calculation:
      # - If coordinate is at peak: scalar = 1.0
      # - If coordinate is between start and peak: linear interpolation
      # - If coordinate is between peak and end: linear interpolation
      # - If coordinate is outside [start, end]: scalar = 0.0
      #
      # Reference: OpenType Font Variations Overview
      # Reference: Adobe Technical Note #5177 (CFF2)
      #
      # @example Calculating scalars
      #   matcher = RegionMatcher.new(regions)
      #   scalars = matcher.calculate_scalars({ "wght" => 0.5, "wdth" => 0.3 })
      class RegionMatcher
        # @return [Array<Hash>] Regions from Variable Store
        attr_reader :regions

        # Initialize matcher with regions
        #
        # @param regions [Array<Hash>] Region definitions from Variable Store
        def initialize(regions)
          @regions = regions
        end

        # Calculate scalars for all regions at given coordinates
        #
        # Coordinates are normalized values in the range [-1.0, 1.0]
        # where 0.0 represents the default/regular style.
        #
        # @param coordinates [Array<Float>] Normalized coordinates per axis
        # @return [Array<Float>] Scalars for each region
        def calculate_scalars(coordinates)
          @regions.map do |region|
            calculate_region_scalar(region, coordinates)
          end
        end

        # Calculate scalar for a single region
        #
        # The scalar is the product of scalars for all axes in the region.
        # If any axis has scalar 0.0, the entire region scalar is 0.0.
        #
        # @param region [Hash] Region definition
        # @param coordinates [Array<Float>] Normalized coordinates per axis
        # @return [Float] Scalar for the region (0.0 to 1.0)
        def calculate_region_scalar(region, coordinates)
          axes = region[:axes]

          # Multiply scalars for all axes
          scalar = 1.0
          axes.each_with_index do |axis, i|
            coord = coordinates[i] || 0.0
            axis_scalar = calculate_axis_scalar(axis, coord)
            scalar *= axis_scalar

            # Early exit if any axis is out of range
            return 0.0 if axis_scalar.zero?
          end

          scalar
        end

        # Calculate scalar for a single axis
        #
        # @param axis [Hash] Axis definition with :start_coord, :peak_coord, :end_coord
        # @param coordinate [Float] Normalized coordinate for this axis
        # @return [Float] Scalar for this axis (0.0 to 1.0)
        def calculate_axis_scalar(axis, coordinate)
          start_coord = axis[:start_coord]
          peak_coord = axis[:peak_coord]
          end_coord = axis[:end_coord]

          # Outside the region
          return 0.0 if coordinate < start_coord || coordinate > end_coord

          # At or beyond peak
          return 1.0 if coordinate == peak_coord

          # Between start and peak
          if coordinate < peak_coord
            # Linear interpolation: (coord - start) / (peak - start)
            range = peak_coord - start_coord
            return 1.0 if range.zero? # Avoid division by zero

            (coordinate - start_coord) / range
          else
            # Between peak and end
            # Linear interpolation: (end - coord) / (end - peak)
            range = end_coord - peak_coord
            return 1.0 if range.zero? # Avoid division by zero

            (end_coord - coordinate) / range
          end
        end

        # Check if coordinates are within any region
        #
        # @param coordinates [Array<Float>] Normalized coordinates
        # @return [Boolean] True if coordinates activate any region
        def coordinates_active?(coordinates)
          scalars = calculate_scalars(coordinates)
          scalars.any?(&:positive?)
        end

        # Get active regions for coordinates
        #
        # Returns indices of regions that have non-zero scalars
        #
        # @param coordinates [Array<Float>] Normalized coordinates
        # @return [Array<Integer>] Indices of active regions
        def active_regions(coordinates)
          scalars = calculate_scalars(coordinates)
          scalars.each_with_index.select { |scalar, _| scalar.positive? }
                 .map(&:last)
        end

        # Get scalar for specific region index
        #
        # @param region_index [Integer] Region index
        # @param coordinates [Array<Float>] Normalized coordinates
        # @return [Float, nil] Scalar for the region, or nil if index invalid
        def scalar_for_region(region_index, coordinates)
          return nil if region_index >= @regions.size

          region = @regions[region_index]
          calculate_region_scalar(region, coordinates)
        end

        # Validate region structure
        #
        # @return [Array<String>] Array of validation errors (empty if valid)
        def validate
          errors = []

          @regions.each_with_index do |region, i|
            axes = region[:axes]
            unless axes.is_a?(Array)
              errors << "Region #{i} has invalid axes (not an array)"
              next
            end

            axes.each_with_index do |axis, j|
              unless axis.is_a?(Hash)
                errors << "Region #{i}, axis #{j} is not a hash"
                next
              end

              # Check required keys
              %i[start_coord peak_coord end_coord].each do |key|
                unless axis.key?(key)
                  errors << "Region #{i}, axis #{j} missing #{key}"
                end
              end

              # Validate coordinate ordering
              if axis[:start_coord] && axis[:peak_coord] && axis[:end_coord]
                start = axis[:start_coord]
                peak = axis[:peak_coord]
                ending = axis[:end_coord]

                unless start <= peak && peak <= ending
                  errors << "Region #{i}, axis #{j} has invalid ordering: " \
                            "#{start} > #{peak} > #{ending}"
                end
              end
            end
          end

          errors
        end

        # Get number of axes from first region
        #
        # @return [Integer] Number of axes
        def axis_count
          return 0 if @regions.empty?

          @regions.first[:axis_count] || @regions.first[:axes]&.size || 0
        end

        # Check if matcher has regions
        #
        # @return [Boolean] True if regions are present
        def has_regions?
          !@regions.empty?
        end
      end
    end
  end
end