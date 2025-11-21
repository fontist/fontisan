# frozen_string_literal: true

module Fontisan
  module Models
    # Represents a glyph's outline data with conversion capabilities
    #
    # [`GlyphOutline`](lib/fontisan/models/glyph_outline.rb) is a pure data
    # model that stores glyph outline information extracted from font tables.
    # It provides methods to convert the outline data to various formats
    # (SVG paths, drawing commands) for rendering and manipulation.
    #
    # The outline consists of:
    # - Contours: Array of closed paths, each containing points
    # - Points: All points from all contours (flattened for easy access)
    # - Bounding box: The glyph's bounding rectangle
    # - Glyph ID: The identifier of this glyph
    #
    # This class is immutable after construction to ensure data integrity.
    #
    # @example Creating an outline
    #   outline = Fontisan::Models::GlyphOutline.new(
    #     glyph_id: 65,
    #     contours: [
    #       [
    #         { x: 100, y: 0, on_curve: true },
    #         { x: 200, y: 700, on_curve: true },
    #         { x: 300, y: 0, on_curve: true }
    #       ]
    #     ],
    #     bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 }
    #   )
    #
    # @example Converting to SVG
    #   svg_path = outline.to_svg_path
    #   # => "M 100 0 L 200 700 L 300 0 Z"
    #
    # @example Getting drawing commands
    #   commands = outline.to_commands
    #   # => [[:move_to, 100, 0], [:line_to, 200, 700], [:line_to, 300, 0], [:close_path]]
    #
    # Reference: [`docs/GETTING_STARTED.md:66-121`](docs/GETTING_STARTED.md:66)
    class GlyphOutline
      # @return [Integer] The glyph identifier
      attr_reader :glyph_id

      # @return [Array<Array<Hash>>] Array of contours, each containing points
      #   Each point hash has keys: :x, :y, :on_curve
      attr_reader :contours

      # @return [Array<Hash>] All points from all contours (flattened)
      attr_reader :points

      # @return [Hash] Bounding box with keys: :x_min, :y_min, :x_max, :y_max
      attr_reader :bbox

      # Initialize a new glyph outline
      #
      # @param glyph_id [Integer] The glyph identifier
      # @param contours [Array<Array<Hash>>] Array of contours, each containing points
      #   Each point must have :x, :y, and :on_curve keys
      # @param bbox [Hash] Bounding box with :x_min, :y_min, :x_max, :y_max keys
      # @raise [ArgumentError] If required parameters are missing or invalid
      def initialize(glyph_id:, contours:, bbox:)
        validate_parameters!(glyph_id, contours, bbox)

        @glyph_id = glyph_id.freeze
        @contours = deep_freeze(contours)
        @points = extract_all_points(contours).freeze
        @bbox = bbox.freeze
      end

      # Convert outline to SVG path data
      #
      # Generates SVG path commands from the outline contours. Each contour
      # becomes a closed path, with move_to for the first point, line_to or
      # curve_to for subsequent points, and an explicit close path.
      #
      # @return [String] SVG path commands (e.g., "M 100 0 L 200 700 Z")
      def to_svg_path
        return "" if empty?

        path_parts = contours.map do |contour|
          build_contour_path(contour)
        end

        path_parts.join(" ")
      end

      # Convert to drawing commands
      #
      # Returns an array of drawing command arrays that can be used to render
      # the glyph. Each command is an array with the command type as the first
      # element and coordinates as subsequent elements.
      #
      # Command types:
      # - :move_to - Move to a point without drawing
      # - :line_to - Draw a straight line to a point
      # - :curve_to - Draw a quadratic Bézier curve (TrueType) or cubic curve (CFF)
      # - :close_path - Close the current path
      #
      # @return [Array<Array>] Array of [command, *args] arrays
      #
      # @example
      #   commands = outline.to_commands
      #   # => [
      #   #   [:move_to, 100, 0],
      #   #   [:line_to, 200, 700],
      #   #   [:line_to, 300, 0],
      #   #   [:close_path]
      #   # ]
      def to_commands
        return [] if empty?

        commands = []
        contours.each do |contour|
          commands.concat(build_contour_commands(contour))
        end
        commands
      end

      # Check if outline is empty (e.g., space glyph)
      #
      # @return [Boolean] True if the glyph has no contours
      def empty?
        contours.empty?
      end

      # Number of points in outline
      #
      # @return [Integer] Total number of points across all contours
      def point_count
        points.length
      end

      # Number of contours in outline
      #
      # @return [Integer] Number of contours
      def contour_count
        contours.length
      end

      # String representation for debugging
      #
      # @return [String] Human-readable representation
      def to_s
        "#<#{self.class.name} glyph_id=#{glyph_id} " \
          "contours=#{contour_count} points=#{point_count} " \
          "bbox=#{bbox.inspect}>"
      end

      alias inspect to_s

      private

      # Validate initialization parameters
      #
      # @param glyph_id [Integer] Glyph ID to validate
      # @param contours [Array] Contours to validate
      # @param bbox [Hash] Bounding box to validate
      # @raise [ArgumentError] If validation fails
      def validate_parameters!(glyph_id, contours, bbox)
        if glyph_id.nil? || !glyph_id.is_a?(Integer) || glyph_id.negative?
          raise ArgumentError,
                "glyph_id must be a non-negative Integer, got: #{glyph_id.inspect}"
        end

        unless contours.is_a?(Array)
          raise ArgumentError,
                "contours must be an Array, got: #{contours.class}"
        end

        unless bbox.is_a?(Hash)
          raise ArgumentError,
                "bbox must be a Hash, got: #{bbox.class}"
        end

        required_bbox_keys = %i[x_min y_min x_max y_max]
        missing_keys = required_bbox_keys - bbox.keys
        unless missing_keys.empty?
          raise ArgumentError,
                "bbox missing required keys: #{missing_keys.join(', ')}"
        end

        # Validate contours structure
        contours.each_with_index do |contour, i|
          unless contour.is_a?(Array)
            raise ArgumentError,
                  "contour #{i} must be an Array, got: #{contour.class}"
          end

          contour.each_with_index do |point, j|
            unless point.is_a?(Hash)
              raise ArgumentError,
                    "point #{j} in contour #{i} must be a Hash, got: #{point.class}"
            end

            required_point_keys = %i[x y on_curve]
            missing_keys = required_point_keys - point.keys
            unless missing_keys.empty?
              raise ArgumentError,
                    "point #{j} in contour #{i} missing keys: #{missing_keys.join(', ')}"
            end
          end
        end
      end

      # Extract all points from contours into a flat array
      #
      # @param contours [Array<Array<Hash>>] Array of contours
      # @return [Array<Hash>] Flattened array of all points
      def extract_all_points(contours)
        contours.flatten(1)
      end

      # Deep freeze nested arrays and hashes for immutability
      #
      # @param obj [Array, Hash, Object] Object to freeze
      # @return [Object] Frozen object
      def deep_freeze(obj)
        case obj
        when Array
          obj.map { |item| deep_freeze(item) }.freeze
        when Hash
          obj.transform_values { |value| deep_freeze(value) }.freeze
        else
          obj.freeze
        end
      end

      # Build SVG path commands for a contour
      #
      # @param contour [Array<Hash>] Array of point hashes
      # @return [String] SVG path string for this contour
      def build_contour_path(contour)
        return "" if contour.empty?

        parts = []
        i = 0

        # Move to first point
        first = contour[i]
        parts << "M #{first[:x]} #{first[:y]}"
        i += 1

        # Process remaining points
        while i < contour.length
          point = contour[i]

          if point[:on_curve]
            # Line to on-curve point
            parts << "L #{point[:x]} #{point[:y]}"
            i += 1
          else
            # Off-curve point - need to handle quadratic curves
            # In TrueType, off-curve points are control points for quadratic Bézier curves
            # If we have consecutive off-curve points, there's an implied on-curve point
            # between them at their midpoint

            control = point
            i += 1

            if i < contour.length && !contour[i][:on_curve]
              # Two consecutive off-curve points
              # Implied on-curve point at midpoint
              next_control = contour[i]
              implied_x = (control[:x] + next_control[:x]) / 2.0
              implied_y = (control[:y] + next_control[:y]) / 2.0
              parts << "Q #{control[:x]} #{control[:y]} #{implied_x} #{implied_y}"
            elsif i < contour.length
              # Next point is on-curve - end of quadratic curve
              end_point = contour[i]
              parts << "Q #{control[:x]} #{control[:y]} #{end_point[:x]} #{end_point[:y]}"
              i += 1
            else
              # Off-curve point is last - curves back to first point
              parts << "Q #{control[:x]} #{control[:y]} #{first[:x]} #{first[:y]}"
            end
          end
        end

        # Close path
        parts << "Z"

        parts.join(" ")
      end

      # Build drawing commands for a contour
      #
      # @param contour [Array<Hash>] Array of point hashes
      # @return [Array<Array>] Array of command arrays
      def build_contour_commands(contour)
        return [] if contour.empty?

        commands = []
        i = 0

        # Move to first point
        first = contour[i]
        commands << [:move_to, first[:x], first[:y]]
        i += 1

        # Process remaining points
        while i < contour.length
          point = contour[i]

          if point[:on_curve]
            # Line to on-curve point
            commands << [:line_to, point[:x], point[:y]]
            i += 1
          else
            # Off-curve point - quadratic curve control point
            control = point
            i += 1

            if i < contour.length && !contour[i][:on_curve]
              # Two consecutive off-curve points
              next_control = contour[i]
              implied_x = (control[:x] + next_control[:x]) / 2.0
              implied_y = (control[:y] + next_control[:y]) / 2.0
              commands << [:curve_to, control[:x], control[:y], implied_x,
                           implied_y]
            elsif i < contour.length
              # Next point is on-curve
              end_point = contour[i]
              commands << [:curve_to, control[:x], control[:y], end_point[:x],
                           end_point[:y]]
              i += 1
            else
              # Curves back to first point
              commands << [:curve_to, control[:x], control[:y], first[:x],
                           first[:y]]
            end
          end
        end

        # Close path
        commands << [:close_path]

        commands
      end
    end
  end
end
