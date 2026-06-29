# frozen_string_literal: true

module Fontisan
  module Ufo
    # An ordered list of points forming one closed (or open) contour
    # in a glyph's outline.
    class Contour
      attr_reader :points

      def initialize(points = [], closed: true)
        @points = points
        @closed = closed
      end

      def closed?
        @closed
      end

      def open?
        !@closed
      end

      def point_count
        @points.size
      end
    end
  end
end
