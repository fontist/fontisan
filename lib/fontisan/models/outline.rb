# frozen_string_literal: true

module Fontisan
  module Models
    # Universal outline representation for format-agnostic glyph outlines
    #
    # [`Outline`](lib/fontisan/models/outline.rb) provides a format-independent
    # representation of glyph outlines that can be converted to/from both
    # TrueType (quadratic) and CFF (cubic) formats. This enables bidirectional
    # TTF ↔ OTF conversion.
    #
    # The outline stores paths as a sequence of drawing commands:
    # - **move_to**: Start a new contour at (x, y)
    # - **line_to**: Draw a line to (x, y)
    # - **quad_to**: Quadratic Bézier curve with control point (cx, cy) to (x, y)
    # - **curve_to**: Cubic Bézier curve with control points (cx1, cy1), (cx2, cy2) to (x, y)
    # - **close_path**: Close the current contour
    #
    # This command-based representation:
    # - Is format-agnostic (works for both TrueType and CFF)
    # - Preserves curve type information
    # - Makes conversion logic clear and testable
    # - Enables easy validation and manipulation
    #
    # @example Creating an outline from commands
    #   outline = Fontisan::Models::Outline.new(
    #     glyph_id: 65,
    #     commands: [
    #       { type: :move_to, x: 100, y: 0 },
    #       { type: :line_to, x: 200, y: 700 },
    #       { type: :line_to, x: 300, y: 0 },
    #       { type: :close_path }
    #     ],
    #     bbox: { x_min: 100, y_min: 0, x_max: 300, y_max: 700 },
    #     width: 400
    #   )
    #
    # @example Converting from TrueType
    #   outline = Fontisan::Models::Outline.from_truetype(glyph, glyph_id)
    #
    # @example Converting from CFF
    #   outline = Fontisan::Models::Outline.from_cff(charstring, glyph_id)
    class Outline
      # @return [Integer] Glyph identifier
      attr_reader :glyph_id

      # @return [Array<Hash>] Array of drawing commands
      #   Each command is a hash with :type and coordinate keys
      attr_reader :commands

      # @return [Hash] Bounding box {:x_min, :y_min, :x_max, :y_max}
      attr_reader :bbox

      # @return [Integer, nil] Advance width (optional)
      attr_reader :width

      # Initialize a new universal outline
      #
      # @param glyph_id [Integer] Glyph identifier
      # @param commands [Array<Hash>] Drawing commands
      # @param bbox [Hash] Bounding box
      # @param width [Integer, nil] Advance width (optional)
      # @raise [ArgumentError] If parameters are invalid
      def initialize(glyph_id:, commands:, bbox:, width: nil)
        validate_parameters!(glyph_id, commands, bbox)

        @glyph_id = glyph_id
        @commands = commands.freeze
        @bbox = bbox.freeze
        @width = width
      end

      # Create outline from TrueType glyph
      #
      # TrueType glyphs use quadratic Bézier curves. This method extracts
      # the contours and converts them to our universal command format.
      #
      # @param glyph [SimpleGlyph, CompoundGlyph] TrueType glyph object
      # @param glyph_id [Integer] Glyph identifier
      # @return [Outline] Universal outline instance
      # @raise [ArgumentError] If glyph is invalid
      def self.from_truetype(glyph, glyph_id)
        raise ArgumentError, "glyph cannot be nil" if glyph.nil?
        raise ArgumentError, "glyph must be simple glyph" unless glyph.simple?

        commands = []
        bbox = {
          x_min: glyph.x_min,
          y_min: glyph.y_min,
          x_max: glyph.x_max,
          y_max: glyph.y_max,
        }

        # Process each contour
        glyph.num_contours.times do |contour_index|
          points = glyph.points_for_contour(contour_index)
          next if points.nil? || points.empty?

          contour_commands = convert_truetype_contour_to_commands(points)
          commands.concat(contour_commands)
        end

        new(
          glyph_id: glyph_id,
          commands: commands,
          bbox: bbox,
        )
      end

      # Create outline from CFF CharString
      #
      # CFF uses cubic Bézier curves. This method executes the CharString
      # and converts the path to our universal command format.
      #
      # @param charstring [CharString] CFF CharString object
      # @param glyph_id [Integer] Glyph identifier
      # @return [Outline] Universal outline instance
      # @raise [ArgumentError] If charstring is invalid
      def self.from_cff(charstring, glyph_id)
        raise ArgumentError, "charstring cannot be nil" if charstring.nil?

        # Get path from CharString
        path = charstring.path
        raise ArgumentError, "CharString has no path data" if path.nil? || path.empty?

        commands = convert_cff_path_to_commands(path)

        # Get bounding box
        bbox_array = charstring.bounding_box
        raise ArgumentError, "CharString has no bounding box" unless bbox_array

        bbox = {
          x_min: bbox_array[0],
          y_min: bbox_array[1],
          x_max: bbox_array[2],
          y_max: bbox_array[3],
        }

        new(
          glyph_id: glyph_id,
          commands: commands,
          bbox: bbox,
        )
      end

      # Convert to TrueType contour format
      #
      # Converts universal commands to TrueType contour format with
      # quadratic curves. Cubic curves are approximated as quadratics.
      #
      # @return [Array<Array<Hash>>] Array of contours
      def to_truetype_contours
        contours = []
        current_contour = []

        commands.each do |cmd|
          case cmd[:type]
          when :move_to
            # Start new contour
            contours << current_contour unless current_contour.empty?
            current_contour = []
            current_contour << {
              x: cmd[:x].round,
              y: cmd[:y].round,
              on_curve: true,
            }
          when :line_to
            current_contour << {
              x: cmd[:x].round,
              y: cmd[:y].round,
              on_curve: true,
            }
          when :quad_to
            # Quadratic curve - add control point and end point
            current_contour << {
              x: cmd[:cx].round,
              y: cmd[:cy].round,
              on_curve: false,
            }
            current_contour << {
              x: cmd[:x].round,
              y: cmd[:y].round,
              on_curve: true,
            }
          when :curve_to
            # Cubic curve - approximate as quadratic
            # Convert cubic Bézier to quadratic (may need multiple segments)
            # For now, use simple midpoint approximation
            control_x = ((cmd[:cx1] + cmd[:cx2]) / 2.0).round
            control_y = ((cmd[:cy1] + cmd[:cy2]) / 2.0).round

            current_contour << {
              x: control_x,
              y: control_y,
              on_curve: false,
            }
            current_contour << {
              x: cmd[:x].round,
              y: cmd[:y].round,
              on_curve: true,
            }
          when :close_path
            # Close contour
            contours << current_contour unless current_contour.empty?
            current_contour = []
          end
        end

        # Add final contour if not closed
        contours << current_contour unless current_contour.empty?

        contours
      end

      # Convert to CFF drawing commands
      #
      # Converts universal commands to CFF CharString format with
      # cubic curves. Quadratic curves are elevation to cubic (exact).
      #
      # @return [Array<Hash>] Array of CFF command hashes
      def to_cff_commands
        cff_commands = []

        commands.each do |cmd|
          case cmd[:type]
          when :move_to
            cff_commands << {
              type: :move_to,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :line_to
            cff_commands << {
              type: :line_to,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :quad_to
            # Quadratic to cubic (degree elevation - exact conversion)
            # For quadratic: P0 (current), P1 (control), P2 (end)
            # Cubic control points: CP1 = P0 + 2/3*(P1 - P0), CP2 = P2 + 2/3*(P1 - P2)
            # We need the previous point (P0)
            prev = find_previous_point(cff_commands)

            cx1 = (prev[:x] + (2.0 / 3.0) * (cmd[:cx] - prev[:x])).round
            cy1 = (prev[:y] + (2.0 / 3.0) * (cmd[:cy] - prev[:y])).round

            cx2 = (cmd[:x] + (2.0 / 3.0) * (cmd[:cx] - cmd[:x])).round
            cy2 = (cmd[:y] + (2.0 / 3.0) * (cmd[:cy] - cmd[:y])).round

            cff_commands << {
              type: :curve_to,
              x1: cx1,
              y1: cy1,
              x2: cx2,
              y2: cy2,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :curve_to
            # Already cubic - direct mapping
            cff_commands << {
              type: :curve_to,
              x1: cmd[:cx1].round,
              y1: cmd[:cy1].round,
              x2: cmd[:cx2].round,
              y2: cmd[:cy2].round,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :close_path
            # CFF doesn't have explicit close - handled by move_to
          end
        end

        cff_commands
      end

      # Check if outline is empty
      #
      # @return [Boolean] True if no drawing commands
      def empty?
        commands.empty? || commands.all? { |cmd| cmd[:type] == :close_path }
      end

      # Get number of commands
      #
      # @return [Integer] Number of commands
      def command_count
        commands.length
      end

      # Get number of contours
      #
      # @return [Integer] Number of contours
      def contour_count
        commands.count { |cmd| cmd[:type] == :move_to }
      end

      # String representation
      #
      # @return [String] Human-readable representation
      def to_s
        "#<#{self.class.name} glyph_id=#{glyph_id} " \
          "commands=#{command_count} contours=#{contour_count} " \
          "bbox=#{bbox.inspect}>"
      end

      alias inspect to_s

      # Apply affine transformation to outline
      #
      # Applies a 2x3 affine transformation matrix to all points in the outline.
      # The matrix is in the format [a, b, c, d, e, f] representing:
      #   x' = a*x + c*y + e
      #   y' = b*x + d*y + f
      #
      # @param matrix [Array<Float>] Transformation matrix [a, b, c, d, e, f]
      # @return [Outline] New outline with transformed commands
      def transform(matrix)
        a, b, c, d, e, f = matrix

        # Transform all commands
        transformed_commands = commands.map do |cmd|
          case cmd[:type]
          when :move_to, :line_to
            {
              type: cmd[:type],
              x: (a * cmd[:x] + c * cmd[:y] + e),
              y: (b * cmd[:x] + d * cmd[:y] + f),
            }
          when :quad_to
            {
              type: :quad_to,
              cx: (a * cmd[:cx] + c * cmd[:cy] + e),
              cy: (b * cmd[:cx] + d * cmd[:cy] + f),
              x: (a * cmd[:x] + c * cmd[:y] + e),
              y: (b * cmd[:x] + d * cmd[:y] + f),
            }
          when :curve_to
            {
              type: :curve_to,
              cx1: (a * cmd[:cx1] + c * cmd[:cy1] + e),
              cy1: (b * cmd[:cx1] + d * cmd[:cy1] + f),
              cx2: (a * cmd[:cx2] + c * cmd[:cy2] + e),
              cy2: (b * cmd[:cx2] + d * cmd[:cy2] + f),
              x: (a * cmd[:x] + c * cmd[:y] + e),
              y: (b * cmd[:x] + d * cmd[:y] + f),
            }
          when :close_path
            cmd
          else
            cmd
          end
        end

        # Calculate transformed bounding box
        # Apply transformation to all four corners
        corners = [
          [bbox[:x_min], bbox[:y_min]],
          [bbox[:x_max], bbox[:y_min]],
          [bbox[:x_min], bbox[:y_max]],
          [bbox[:x_max], bbox[:y_max]],
        ].map do |x, y|
          [a * x + c * y + e, b * x + d * y + f]
        end

        x_coords = corners.map(&:first)
        y_coords = corners.map(&:last)

        transformed_bbox = {
          x_min: x_coords.min.round,
          y_min: y_coords.min.round,
          x_max: x_coords.max.round,
          y_max: y_coords.max.round,
        }

        Outline.new(
          glyph_id: glyph_id,
          commands: transformed_commands,
          bbox: transformed_bbox,
          width: width,
        )
      end

      # Merge another outline into this one
      #
      # Combines the commands from another outline with this one,
      # creating a composite outline. The bounding box is recalculated
      # to encompass both outlines.
      #
      # @param other [Outline] Outline to merge
      # @return [void]
      def merge!(other)
        return if other.empty?

        # Merge commands (skip close_path before adding new contours)
        merged_commands = commands.dup
        merged_commands.pop if merged_commands.last && merged_commands.last[:type] == :close_path

        # Add other's commands
        merged_commands.concat(other.commands)

        # Recalculate bounding box
        merged_bbox = {
          x_min: [bbox[:x_min], other.bbox[:x_min]].min,
          y_min: [bbox[:y_min], other.bbox[:y_min]].min,
          x_max: [bbox[:x_max], other.bbox[:x_max]].max,
          y_max: [bbox[:y_max], other.bbox[:y_max]].max,
        }

        # Update instance variables
        @commands = merged_commands.freeze
        @bbox = merged_bbox.freeze
      end

      private

      # Validate initialization parameters
      #
      # @param glyph_id [Integer] Glyph ID
      # @param commands [Array] Commands array
      # @param bbox [Hash] Bounding box
      # @raise [ArgumentError] If validation fails
      def validate_parameters!(glyph_id, commands, bbox)
        if glyph_id.nil? || !glyph_id.is_a?(Integer) || glyph_id.negative?
          raise ArgumentError,
                "glyph_id must be non-negative Integer, got: #{glyph_id.inspect}"
        end

        unless commands.is_a?(Array)
          raise ArgumentError,
                "commands must be Array, got: #{commands.class}"
        end

        unless bbox.is_a?(Hash)
          raise ArgumentError,
                "bbox must be Hash, got: #{bbox.class}"
        end

        required_keys = %i[x_min y_min x_max y_max]
        missing_keys = required_keys - bbox.keys
        unless missing_keys.empty?
          raise ArgumentError,
                "bbox missing keys: #{missing_keys.join(', ')}"
        end

        # Validate commands
        commands.each_with_index do |cmd, i|
          unless cmd.is_a?(Hash) && cmd.key?(:type)
            raise ArgumentError,
                  "command #{i} must be Hash with :type key"
          end

          validate_command!(cmd, i)
        end
      end

      # Validate individual command
      #
      # @param cmd [Hash] Command to validate
      # @param index [Integer] Command index (for error messages)
      # @raise [ArgumentError] If command is invalid
      def validate_command!(cmd, index)
        case cmd[:type]
        when :move_to, :line_to
          unless cmd.key?(:x) && cmd.key?(:y)
            raise ArgumentError,
                  "command #{index} (#{cmd[:type]}) missing :x or :y"
          end
        when :quad_to
          unless cmd.key?(:cx) && cmd.key?(:cy) && cmd.key?(:x) && cmd.key?(:y)
            raise ArgumentError,
                  "command #{index} (quad_to) missing required keys"
          end
        when :curve_to
          required = %i[cx1 cy1 cx2 cy2 x y]
          missing = required - cmd.keys
          unless missing.empty?
            raise ArgumentError,
                  "command #{index} (curve_to) missing keys: #{missing.join(', ')}"
          end
        when :close_path
          # No additional validation needed
        else
          raise ArgumentError,
                "command #{index} has invalid type: #{cmd[:type]}"
        end
      end

      # Convert TrueType contour points to commands
      #
      # @param points [Array<Hash>] Array of points with :x, :y, :on_curve
      # @return [Array<Hash>] Array of commands
      def self.convert_truetype_contour_to_commands(points)
        return [] if points.empty?

        commands = []
        i = 0

        # Move to first point
        first = points[i]
        commands << { type: :move_to, x: first[:x], y: first[:y] }
        i += 1

        # Process remaining points
        while i < points.length
          point = points[i]

          if point[:on_curve]
            # Line to on-curve point
            commands << { type: :line_to, x: point[:x], y: point[:y] }
            i += 1
          else
            # Off-curve point - quadratic curve control point
            control = point
            i += 1

            if i < points.length && !points[i][:on_curve]
              # Two consecutive off-curve points - implied on-curve at midpoint
              next_control = points[i]
              implied_x = (control[:x] + next_control[:x]) / 2.0
              implied_y = (control[:y] + next_control[:y]) / 2.0

              commands << {
                type: :quad_to,
                cx: control[:x],
                cy: control[:y],
                x: implied_x,
                y: implied_y,
              }
            elsif i < points.length
              # Next point is on-curve - end of quadratic curve
              end_point = points[i]
              commands << {
                type: :quad_to,
                cx: control[:x],
                cy: control[:y],
                x: end_point[:x],
                y: end_point[:y],
              }
              i += 1
            else
              # Curves back to first point
              commands << {
                type: :quad_to,
                cx: control[:x],
                cy: control[:y],
                x: first[:x],
                y: first[:y],
              }
            end
          end
        end

        # Close path
        commands << { type: :close_path }

        commands
      end

      # Convert CFF path to universal commands
      #
      # CFF doesn't have explicit closepath operators - contours are implicitly
      # closed when a new moveto starts or at endchar. We add explicit
      # close_path commands only when the contour is geometrically closed
      # (last point equals first point), to preserve open contours from TTF.
      #
      # @param path [Array<Hash>] CFF path data
      # @return [Array<Hash>] Universal commands
      def self.convert_cff_path_to_commands(path)
        commands = []
        contour_start = nil # Track the start point of current contour

        path.each_with_index do |cmd, _index|
          case cmd[:type]
          when :move_to
            # Before starting new contour, close previous one if it was geometrically closed
            if contour_start && !commands.empty? && commands.last[:type] != :close_path
              # Check if last point equals start point (contour is closed)
              last_cmd = commands.last
              last_point = case last_cmd[:type]
                           when :line_to
                             { x: last_cmd[:x], y: last_cmd[:y] }
                           when :curve_to
                             { x: last_cmd[:x], y: last_cmd[:y] }
                           end

              if last_point &&
                  (last_point[:x] - contour_start[:x]).abs <= 1 &&
                  (last_point[:y] - contour_start[:y]).abs <= 1
                # Contour is geometrically closed
                commands << { type: :close_path }
              end
            end

            # Start new contour
            contour_start = { x: cmd[:x].round, y: cmd[:y].round }
            commands << {
              type: :move_to,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :line_to
            commands << {
              type: :line_to,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          when :curve_to
            # CFF cubic curve
            commands << {
              type: :curve_to,
              cx1: cmd[:x1].round,
              cy1: cmd[:y1].round,
              cx2: cmd[:x2].round,
              cy2: cmd[:y2].round,
              x: cmd[:x].round,
              y: cmd[:y].round,
            }
          end
        end

        # Close the final contour if it was geometrically closed
        if contour_start && !commands.empty? && commands.last[:type] != :close_path
          last_cmd = commands.last
          last_point = case last_cmd[:type]
                       when :line_to
                         { x: last_cmd[:x], y: last_cmd[:y] }
                       when :curve_to
                         { x: last_cmd[:x], y: last_cmd[:y] }
                       end

          if last_point &&
              (last_point[:x] - contour_start[:x]).abs <= 1 &&
              (last_point[:y] - contour_start[:y]).abs <= 1
            # Contour is geometrically closed
            commands << { type: :close_path }
          end
        end

        commands
      end

      # Find previous point from commands
      #
      # @param commands [Array<Hash>] CFF commands
      # @return [Hash] Previous point {:x, :y}
      def find_previous_point(commands)
        commands.reverse_each do |cmd|
          case cmd[:type]
          when :move_to, :line_to
            return { x: cmd[:x], y: cmd[:y] }
          when :curve_to
            return { x: cmd[:x], y: cmd[:y] }
          end
        end

        # Default to origin if no previous point found
        { x: 0, y: 0 }
      end
    end
  end
end
