# frozen_string_literal: true

require_relative "delta_parser"
require_relative "interpolator"
require_relative "region_matcher"
require_relative "table_accessor"

module Fontisan
  module Variation
    # Applies variation deltas to glyph outlines
    #
    # This class handles the complete delta application process for TrueType
    # variable fonts using gvar table data:
    # 1. Parse base glyph outline points
    # 2. Match active tuple variations to coordinates
    # 3. Parse and decompress deltas
    # 4. Apply deltas: new_point = base + Σ(delta × scalar)
    # 5. Expand IUP (Inferred Untouched Points)
    #
    # Reference: OpenType specification, gvar table
    #
    # @example Applying deltas to a glyph
    #   applier = Fontisan::Variation::DeltaApplier.new(font, interpolator, region_matcher)
    #   adjusted_points = applier.apply_deltas(glyph_id, coordinates)
    class DeltaApplier
      include TableAccessor

      # @return [Font] Font object
      attr_reader :font

      # @return [Interpolator] Coordinate interpolator
      attr_reader :interpolator

      # @return [RegionMatcher] Region matcher
      attr_reader :region_matcher

      # @return [DeltaParser] Delta parser
      attr_reader :delta_parser

      # Initialize delta applier
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font with gvar table
      # @param interpolator [Interpolator] Coordinate interpolator
      # @param region_matcher [RegionMatcher] Region matcher
      def initialize(font, interpolator, region_matcher)
        @font = font
        @interpolator = interpolator
        @region_matcher = region_matcher
        @delta_parser = DeltaParser.new
        @variation_tables = {}
      end

      # Apply deltas to a glyph at given coordinates
      #
      # @param glyph_id [Integer] Glyph ID
      # @param coordinates [Hash<String, Float>] Design space coordinates
      # @return [Array<Hash>, nil] Adjusted points or nil if not applicable
      def apply_deltas(glyph_id, coordinates)
        gvar = variation_table("gvar")
        glyf = variation_table("glyf")
        return nil unless gvar && glyf

        # Get base glyph outline points
        base_points = extract_glyph_points(glyph_id, glyf)
        return nil if base_points.nil? || base_points.empty?

        # Get tuple variations for this glyph
        tuple_data = gvar.glyph_tuple_variations(glyph_id)
        return base_points if tuple_data.nil? || tuple_data[:tuples].empty?

        # Match active tuples to coordinates
        matches = @region_matcher.match_tuples(
          coordinates: coordinates,
          tuples: tuple_data[:tuples],
        )

        return base_points if matches.empty?

        # Apply each active tuple's deltas
        adjusted_points = base_points.dup
        matches.each do |match|
          apply_tuple_deltas(adjusted_points, match, tuple_data, base_points.length)
        end

        adjusted_points
      end

      # Extract outline points from glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @param glyf [Glyf] Glyf table
      # @return [Array<Hash>, nil] Array of points with :x, :y, :on_curve
      def extract_glyph_points(glyph_id, glyf)
        # This is a simplified version - full implementation would parse
        # complete glyf table data including composite glyphs
        glyph_data = glyf.glyph_data(glyph_id)
        return nil if glyph_data.nil?

        # Parse glyph outline (simplified)
        # Real implementation would fully parse SimpleGlyph or CompositeGlyph
        []
      end

      private

      # Apply a single tuple's deltas to points
      #
      # @param points [Array<Hash>] Points to adjust (modified in place)
      # @param match [Hash] Matched tuple with :tuple and :scalar
      # @param tuple_data [Hash] Complete tuple data from gvar
      # @param point_count [Integer] Number of points
      def apply_tuple_deltas(points, match, tuple_data, point_count)
        tuple = match[:tuple]
        scalar = match[:scalar]

        return if scalar.zero?

        # Parse deltas for this tuple
        # Note: In real implementation, we'd need to extract the actual
        # delta data from the gvar table at the correct offset
        deltas = parse_tuple_deltas(tuple, point_count, tuple_data)
        return if deltas.nil?

        # Check if points need IUP expansion
        if tuple[:private_points]
          # Expand IUP for untouched points
          deltas = expand_iup(deltas, point_count)
        end

        # Apply deltas with scalar
        points.each_with_index do |point, i|
          next if i >= deltas.length

          delta = deltas[i]
          point[:x] += delta[:x] * scalar
          point[:y] += delta[:y] * scalar
        end
      end

      # Parse deltas for a tuple variation
      #
      # @param tuple [Hash] Tuple variation info
      # @param point_count [Integer] Number of points
      # @param tuple_data [Hash] Complete tuple data
      # @return [Array<Hash>, nil] Array of point deltas
      def parse_tuple_deltas(tuple, point_count, tuple_data)
        # In real implementation, this would:
        # 1. Calculate offset to delta data
        # 2. Extract raw delta bytes
        # 3. Call delta_parser.parse with appropriate flags

        # Placeholder - full implementation needs access to raw delta data
        @delta_parser.parse(
          "",
          point_count,
          private_points: tuple[:private_points],
          shared_points: tuple_data[:has_shared_points] ? [] : nil,
        )
      end

      # Expand IUP (Inferred Untouched Points)
      #
      # Points without explicit deltas have their deltas inferred through
      # linear interpolation between surrounding touched points.
      #
      # @param deltas [Array<Hash>] Delta array (sparse)
      # @param point_count [Integer] Total number of points
      # @return [Array<Hash>] Expanded delta array
      def expand_iup(deltas, point_count)
        return deltas if deltas.length == point_count

        expanded = Array.new(point_count) { { x: 0, y: 0 } }

        # Copy explicit deltas
        deltas.each_with_index do |delta, i|
          next if i >= point_count

          expanded[i] = delta if delta[:x] != 0 || delta[:y] != 0
        end

        # Find touched points
        touched = []
        deltas.each_with_index do |delta, i|
          touched << i if delta[:x] != 0 || delta[:y] != 0
        end

        return expanded if touched.empty?

        # Infer untouched points
        point_count.times do |i|
          next if touched.include?(i)

          # Find previous and next touched points
          prev_idx = find_previous_touched(touched, i)
          next_idx = find_next_touched(touched, i, point_count)

          # Interpolate delta
          if prev_idx && next_idx
            expanded[i] = interpolate_delta(
              deltas[prev_idx],
              deltas[next_idx],
              i, prev_idx, next_idx
            )
          elsif prev_idx
            # Use previous delta
            expanded[i] = deltas[prev_idx].dup
          elsif next_idx
            # Use next delta
            expanded[i] = deltas[next_idx].dup
          end
        end

        expanded
      end

      # Find previous touched point
      #
      # @param touched [Array<Integer>] Touched point indices
      # @param index [Integer] Current point index
      # @return [Integer, nil] Previous touched index or nil
      def find_previous_touched(touched, index)
        touched.reverse_each do |t|
          return t if t < index
        end
        nil
      end

      # Find next touched point
      #
      # @param touched [Array<Integer>] Touched point indices
      # @param index [Integer] Current point index
      # @param point_count [Integer] Total points (for wrapping)
      # @return [Integer, nil] Next touched index or nil
      def find_next_touched(touched, index, _point_count)
        # Check forward
        touched.each do |t|
          return t if t > index
        end

        # Wrap around (contour is closed)
        touched.first
      end

      # Interpolate delta between two touched points
      #
      # @param delta1 [Hash] First delta
      # @param delta2 [Hash] Second delta
      # @param current [Integer] Current point index
      # @param idx1 [Integer] First point index
      # @param idx2 [Integer] Second point index
      # @return [Hash] Interpolated delta
      def interpolate_delta(delta1, delta2, current, idx1, idx2)
        # Linear interpolation
        range = idx2 - idx1
        return delta1.dup if range.zero?

        ratio = (current - idx1).to_f / range

        {
          x: delta1[:x] + (delta2[:x] - delta1[:x]) * ratio,
          y: delta1[:y] + (delta2[:y] - delta1[:y]) * ratio,
        }
      end
    end
  end
end
