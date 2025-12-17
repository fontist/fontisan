# frozen_string_literal: true

module Fontisan
  module Variation
    # Region matcher for variable fonts
    #
    # This class matches design space coordinates to variation regions/tuples,
    # determining which regions contribute to the final interpolated value
    # and calculating their contribution scalars.
    #
    # A variation region defines a sub-space within the design space where
    # a particular set of deltas applies. Regions are defined by start, peak,
    # and end coordinates on each axis.
    #
    # Matching Process:
    # 1. For each region, check if current coordinates fall within the region
    # 2. Calculate the scalar (contribution factor) for each matching region
    # 3. Return only non-zero contributions
    #
    # Reference: OpenType Font Variations specification, gvar table
    #
    # @example Matching coordinates to regions
    #   matcher = RegionMatcher.new(axes)
    #   matches = matcher.match_regions(
    #     coordinates: { "wght" => 600.0 },
    #     regions: [region1, region2, region3]
    #   )
    #   # => [{ region_index: 0, scalar: 0.5 }, { region_index: 1, scalar: 0.8 }]
    class RegionMatcher
      # @return [Array<VariationAxisRecord>] Variation axes
      attr_reader :axes

      # @return [Interpolator] Coordinate interpolator
      attr_reader :interpolator

      # Initialize region matcher
      #
      # @param axes [Array<VariationAxisRecord>] Variation axes from fvar table
      def initialize(axes)
        @axes = axes || []
        @interpolator = Interpolator.new(@axes)
      end

      # Match coordinates to variation regions
      #
      # Returns all regions that contribute (have non-zero scalar) at the
      # given coordinates, along with their contribution scalars.
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param regions [Array<Hash>] Array of region definitions
      # @return [Array<Hash>] Matches with :region_index and :scalar
      def match_regions(coordinates:, regions:)
        # Normalize coordinates
        normalized = @interpolator.normalize_coordinates(coordinates)

        # Find matching regions
        matches = []
        regions.each_with_index do |region, index|
          scalar = @interpolator.calculate_region_scalar(normalized, region)

          # Only include non-zero contributions
          matches << { region_index: index, scalar: scalar } if scalar > 0.0
        end

        matches
      end

      # Match coordinates to gvar tuple variations
      #
      # Converts gvar tuple data to regions and matches them.
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param tuples [Array<Hash>] Tuple variation data from gvar
      # @return [Array<Hash>] Matches with :tuple_index and :scalar
      def match_tuples(coordinates:, tuples:)
        # Convert tuples to regions
        regions = tuples.map do |tuple|
          @interpolator.build_region_from_tuple(tuple)
        end

        # Match regions
        match_regions(coordinates: coordinates, regions: regions)
      end

      # Check if coordinates are within a region
      #
      # @param coordinates [Hash<String, Float>] Normalized coordinates
      # @param region [Hash<String, Hash>] Region definition per axis
      # @return [Boolean] True if within region
      def within_region?(coordinates, region)
        region.all? do |axis_tag, axis_region|
          coord = coordinates[axis_tag] || 0.0
          start_val = axis_region[:start] || -1.0
          end_val = axis_region[:end] || 1.0

          coord >= start_val && coord <= end_val
        end
      end

      # Get active regions at coordinates
      #
      # Returns the subset of regions that are active (non-zero contribution)
      # at the given coordinates.
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param regions [Array<Hash>] All regions
      # @return [Array<Integer>] Indices of active regions
      def active_region_indices(coordinates, regions)
        matches = match_regions(coordinates: coordinates, regions: regions)
        matches.map { |m| m[:region_index] }
      end

      # Calculate contribution percentages for all regions
      #
      # Returns the percentage contribution of each region at the given
      # coordinates. All percentages sum to 100% (or less if some regions
      # are inactive).
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param regions [Array<Hash>] All regions
      # @return [Array<Float>] Contribution percentages (0.0 to 1.0)
      def contribution_percentages(coordinates, regions)
        matches = match_regions(coordinates: coordinates, regions: regions)

        # Calculate total scalar
        total_scalar = matches.sum { |m| m[:scalar] }
        return Array.new(regions.size, 0.0) if total_scalar.zero?

        # Build percentage array
        percentages = Array.new(regions.size, 0.0)
        matches.each do |match|
          percentages[match[:region_index]] = match[:scalar] / total_scalar
        end

        percentages
      end

      # Find the dominant region at coordinates
      #
      # Returns the region with the highest contribution scalar.
      #
      # @param coordinates [Hash<String, Float>] User-space coordinates
      # @param regions [Array<Hash>] All regions
      # @return [Hash, nil] Match with highest scalar or nil
      def dominant_region(coordinates, regions)
        matches = match_regions(coordinates: coordinates, regions: regions)
        return nil if matches.empty?

        matches.max_by { |m| m[:scalar] }
      end

      # Build region from peak coordinates
      #
      # Creates a simple region definition from peak coordinates only,
      # using ±1.0 for start/end on each axis.
      #
      # @param peaks [Hash<String, Float>] Peak coordinates per axis
      # @return [Hash<String, Hash>] Region definition
      def build_region_from_peaks(peaks)
        region = {}

        @axes.each do |axis|
          tag = axis.axis_tag
          peak = peaks[tag] || 0.0

          region[tag] = {
            start: peak.negative? ? -1.0 : 0.0,
            peak: peak,
            end: peak.positive? ? 1.0 : 0.0,
          }
        end

        region
      end

      # Build region from start, peak, end arrays
      #
      # Converts array-based region data (as in gvar) to hash-based format.
      #
      # @param start_arr [Array<Float>] Start coordinates (one per axis)
      # @param peak_arr [Array<Float>] Peak coordinates (one per axis)
      # @param end_arr [Array<Float>] End coordinates (one per axis)
      # @return [Hash<String, Hash>] Region definition
      def build_region_from_arrays(start_arr, peak_arr, end_arr)
        region = {}

        @axes.each_with_index do |axis, index|
          region[axis.axis_tag] = {
            start: start_arr[index] || -1.0,
            peak: peak_arr[index] || 0.0,
            end: end_arr[index] || 1.0,
          }
        end

        region
      end

      # Validate region definition
      #
      # Checks if a region is well-formed.
      #
      # @param region [Hash<String, Hash>] Region definition
      # @return [Boolean] True if valid
      def valid_region?(region)
        return false unless region.is_a?(Hash)

        region.all? do |_axis_tag, axis_region|
          next false unless axis_region.is_a?(Hash)
          next false unless axis_region.key?(:peak)

          start_val = axis_region[:start] || -1.0
          peak = axis_region[:peak]
          end_val = axis_region[:end] || 1.0

          # Validate ordering: start <= peak <= end
          start_val <= peak && peak <= end_val
        end
      end
    end
  end
end
