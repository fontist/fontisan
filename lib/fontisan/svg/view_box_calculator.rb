# frozen_string_literal: true

module Fontisan
  module Svg
    # Calculates SVG viewBox and handles coordinate transformations
    #
    # [`ViewBoxCalculator`](lib/fontisan/svg/view_box_calculator.rb) manages
    # the coordinate system transformation between font space and SVG space.
    # Font coordinates use a Y-up system (ascender is positive), while SVG
    # uses Y-down (origin at top-left).
    #
    # Responsibilities:
    # - Calculate appropriate viewBox for glyphs
    # - Transform Y-coordinates (flip Y-axis)
    # - Scale coordinates based on units-per-em
    # - Provide consistent coordinate mapping
    #
    # This is a pure utility class with no state or side effects.
    #
    # @example Transform a Y coordinate
    #   calculator = ViewBoxCalculator.new(units_per_em: 1000, ascent: 800, descent: -200)
    #   svg_y = calculator.transform_y(700)  # Font Y to SVG Y
    #
    # @example Calculate viewBox for a glyph
    #   viewbox = calculator.calculate_viewbox(x_min: 100, y_min: 0, x_max: 600, y_max: 700)
    #   # => "100 100 500 700"
    class ViewBoxCalculator
      # @return [Integer] Units per em from font
      attr_reader :units_per_em

      # @return [Integer] Font ascent
      attr_reader :ascent

      # @return [Integer] Font descent (typically negative)
      attr_reader :descent

      # Initialize calculator with font metrics
      #
      # @param units_per_em [Integer] Units per em from font head table
      # @param ascent [Integer] Font ascent from hhea table
      # @param descent [Integer] Font descent from hhea table (typically negative)
      # @raise [ArgumentError] If parameters are invalid
      def initialize(units_per_em:, ascent:, descent:)
        validate_parameters!(units_per_em, ascent, descent)

        @units_per_em = units_per_em
        @ascent = ascent
        @descent = descent
      end

      # Transform Y coordinate from font space to SVG space
      #
      # Font space: Y-up (ascender positive, descender negative)
      # SVG space: Y-down (origin at top)
      #
      # Transformation: svg_y = ascent - font_y
      #
      # @param font_y [Numeric] Y coordinate in font space
      # @return [Numeric] Y coordinate in SVG space
      def transform_y(font_y)
        ascent - font_y
      end

      # Transform point from font space to SVG space
      #
      # @param font_x [Numeric] X coordinate in font space
      # @param font_y [Numeric] Y coordinate in font space
      # @return [Array<Numeric>] [svg_x, svg_y]
      def transform_point(font_x, font_y)
        [font_x, transform_y(font_y)]
      end

      # Calculate viewBox string for SVG
      #
      # @param x_min [Numeric] Minimum X coordinate
      # @param y_min [Numeric] Minimum Y coordinate
      # @param x_max [Numeric] Maximum X coordinate
      # @param y_max [Numeric] Maximum Y coordinate
      # @return [String] ViewBox string "x y width height"
      def calculate_viewbox(x_min:, y_min:, x_max:, y_max:)
        # Transform bounding box to SVG space
        svg_y_min = transform_y(y_max) # Y is flipped
        svg_y_max = transform_y(y_min)

        width = x_max - x_min
        height = svg_y_max - svg_y_min

        "#{x_min} #{svg_y_min} #{width} #{height}"
      end

      # Calculate font-level viewBox
      #
      # Uses font metrics to create a viewBox covering the entire font space
      #
      # @return [String] ViewBox string for entire font
      def font_viewbox
        # Typical font viewBox covers descent to ascent
        # Width is units_per_em
        height = ascent - descent
        "0 0 #{units_per_em} #{height}"
      end

      # Get scale factor for coordinate precision
      #
      # @param target_units [Integer] Target units per em (default 1000)
      # @return [Float] Scale factor
      def scale_factor(target_units: 1000)
        target_units.to_f / units_per_em
      end

      private

      # Validate initialization parameters
      #
      # @param units_per_em [Integer] Units per em
      # @param ascent [Integer] Font ascent
      # @param descent [Integer] Font descent
      # @raise [ArgumentError] If validation fails
      def validate_parameters!(units_per_em, ascent, descent)
        unless units_per_em.is_a?(Integer) && units_per_em.positive?
          raise ArgumentError,
                "units_per_em must be a positive Integer, got: #{units_per_em.inspect}"
        end

        unless ascent.is_a?(Integer)
          raise ArgumentError,
                "ascent must be an Integer, got: #{ascent.inspect}"
        end

        unless descent.is_a?(Integer)
          raise ArgumentError,
                "descent must be an Integer, got: #{descent.inspect}"
        end
      end
    end
  end
end
