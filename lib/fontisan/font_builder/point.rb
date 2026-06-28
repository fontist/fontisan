# frozen_string_literal: true

module Fontisan
  module FontBuilder
    # Single point in a TrueType outline. On-curve points define the
    # path; off-curve points are quadratic Bezier control points.
    #
    # The font's glyf table encodes each contour as a sequence of
    # Points with flag bits. Coordinates are signed integers in font
    # units (unitsPerEm, typically 1000 or 2048).
    Point = Struct.new(:x, :y, :on_curve, keyword_init: true) do
      def initialize(x: 0, y: 0, on_curve: true)
        super
      end

      # Compact representation used by glyf table encoding.
      # Coordinates are delta-encoded against the previous point.
      def delta(previous)
        prev = previous || Point.new
        Point.new(x: x - prev.x, y: y - prev.y, on_curve: on_curve)
      end
    end
  end
end
