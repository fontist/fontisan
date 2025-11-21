# frozen_string_literal: true

require_relative "view_box_calculator"

module Fontisan
  module Svg
    # Generates SVG glyph elements from glyph outlines
    #
    # [`GlyphGenerator`](lib/fontisan/svg/glyph_generator.rb) converts
    # [`GlyphOutline`](lib/fontisan/models/glyph_outline.rb) objects to SVG
    # `<glyph>` elements with proper path data and coordinate transformations.
    #
    # Responsibilities:
    # - Transform glyph outline to SVG path with Y-axis flip
    # - Generate SVG glyph element with attributes
    # - Handle unicode and glyph name mapping
    # - Calculate horizontal advance width
    # - Format path data with proper precision
    #
    # This class uses ViewBoxCalculator for coordinate transformations and
    # GlyphOutline's to_svg_path method for path generation.
    #
    # @example Generate SVG glyph element
    #   generator = GlyphGenerator.new(calculator)
    #   xml = generator.generate_glyph_xml(outline, unicode: "A", advance_width: 600)
    class GlyphGenerator
      # @return [ViewBoxCalculator] Coordinate calculator
      attr_reader :calculator

      # Initialize generator with calculator
      #
      # @param calculator [ViewBoxCalculator] Coordinate transformation calculator
      # @raise [ArgumentError] If calculator is nil
      def initialize(calculator)
        raise ArgumentError, "Calculator cannot be nil" if calculator.nil?

        @calculator = calculator
      end

      # Generate SVG glyph element
      #
      # @param outline [Models::GlyphOutline] Glyph outline
      # @param unicode [String, nil] Unicode character
      # @param glyph_name [String, nil] Glyph name
      # @param advance_width [Integer] Horizontal advance width
      # @param indent [String] Indentation string
      # @return [String] XML glyph element
      def generate_glyph_xml(outline, unicode: nil, glyph_name: nil,
advance_width: 0, indent: "      ")
        # Build attribute parts
        attr_parts = []

        attr_parts << "unicode=\"#{escape_xml(unicode)}\"" if unicode
        attr_parts << "glyph-name=\"#{escape_xml(glyph_name)}\"" if glyph_name
        attr_parts << "horiz-adv-x=\"#{advance_width}\"" if advance_width&.positive?

        # Generate SVG path with Y-axis transformation
        path_data = generate_svg_path(outline)
        attr_parts << "d=\"#{path_data}\"" if path_data && !path_data.empty?

        "#{indent}<glyph #{attr_parts.join(' ')}/>"
      end

      # Generate missing-glyph element
      #
      # @param advance_width [Integer] Default advance width
      # @param indent [String] Indentation string
      # @return [String] XML missing-glyph element
      def generate_missing_glyph(advance_width: 500, indent: "      ")
        "#{indent}<missing-glyph horiz-adv-x=\"#{advance_width}\"/>"
      end

      # Generate SVG path data with coordinate transformation
      #
      # Transforms the glyph outline from font space to SVG space by flipping
      # the Y-axis. Font coordinates use Y-up (ascender positive), while SVG
      # uses Y-down (origin at top).
      #
      # @param outline [Models::GlyphOutline] Glyph outline
      # @return [String] SVG path data
      def generate_svg_path(outline)
        return "" if outline.empty?

        path_parts = outline.contours.map do |contour|
          build_transformed_contour_path(contour)
        end

        path_parts.join(" ")
      end

      private

      # Build SVG path for a contour with Y-axis transformation
      #
      # @param contour [Array<Hash>] Array of point hashes
      # @return [String] SVG path string for this contour
      def build_transformed_contour_path(contour)
        return "" if contour.empty?

        parts = []
        i = 0

        # Move to first point (with Y-axis flip)
        first = contour[i]
        svg_y = calculator.transform_y(first[:y])
        parts << "M #{first[:x]} #{svg_y}"
        i += 1

        # Process remaining points
        while i < contour.length
          point = contour[i]

          if point[:on_curve]
            # Line to on-curve point (with Y-axis flip)
            svg_y = calculator.transform_y(point[:y])
            parts << "L #{point[:x]} #{svg_y}"
            i += 1
          else
            # Off-curve point - quadratic curve control point
            control = point
            control_svg_y = calculator.transform_y(control[:y])
            i += 1

            if i < contour.length && !contour[i][:on_curve]
              # Two consecutive off-curve points
              # Implied on-curve point at midpoint
              next_control = contour[i]
              implied_x = (control[:x] + next_control[:x]) / 2.0
              implied_y = (control[:y] + next_control[:y]) / 2.0
              implied_svg_y = calculator.transform_y(implied_y)
              parts << "Q #{control[:x]} #{control_svg_y} #{implied_x} #{implied_svg_y}"
            elsif i < contour.length
              # Next point is on-curve - end of quadratic curve
              end_point = contour[i]
              end_svg_y = calculator.transform_y(end_point[:y])
              parts << "Q #{control[:x]} #{control_svg_y} #{end_point[:x]} #{end_svg_y}"
              i += 1
            else
              # Off-curve point is last - curves back to first point
              first_svg_y = calculator.transform_y(first[:y])
              parts << "Q #{control[:x]} #{control_svg_y} #{first[:x]} #{first_svg_y}"
            end
          end
        end

        # Close path
        parts << "Z"

        parts.join(" ")
      end

      # Escape XML special characters
      #
      # @param text [String, nil] Text to escape
      # @return [String] Escaped text
      def escape_xml(text)
        return "" if text.nil?

        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&apos;")
      end
    end
  end
end
