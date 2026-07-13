# frozen_string_literal: true

module Fontisan
  module Ufo
    # Immutable axis-aligned bounding box over outline points.
    #
    # Bounds is a value object: equality and hash are based on the four
    # coordinates, not identity. Bounds composes via #union so callers
    # can fold bounds across many contours or many glyphs without
    # mutating either side.
    class Bounds
      include Comparable

      attr_reader :min_x, :min_y, :max_x, :max_y

      def initialize(min_x:, min_y:, max_x:, max_y:)
        @min_x = min_x.to_f
        @min_y = min_y.to_f
        @max_x = max_x.to_f
        @max_y = max_y.to_f
      end

      # @param contours [Array<Contour>, Enumerable<Contour>]
      # @return [Bounds]
      def self.measure(contours)
        min_x = min_y = +Float::INFINITY
        max_x = max_y = -Float::INFINITY
        saw_point = false

        contours.each do |contour|
          contour.points.each do |pt|
            saw_point = true
            min_x = pt.x if pt.x < min_x
            min_y = pt.y if pt.y < min_y
            max_x = pt.x if pt.x > max_x
            max_y = pt.y if pt.y > max_y
          end
        end

        return empty unless saw_point

        new(min_x: min_x, min_y: min_y, max_x: max_x, max_y: max_y)
      end

      # @return [Bounds] zero-extent bounds anchored at the origin
      def self.empty
        new(min_x: 0, min_y: 0, max_x: 0, max_y: 0)
      end

      def width
        max_x - min_x
      end

      def height
        max_y - min_y
      end

      # A bounds is empty when it has zero extent in both axes. Note that
      # a contour containing a single point yields zero-extent bounds but
      # is not "empty" in the geometric sense — callers that need to
      # distinguish should test the contour directly.
      def empty?
        width.zero? && height.zero?
      end

      # Smallest bounds containing both self and other.
      #
      # @param other [Bounds]
      # @return [Bounds]
      def union(other)
        self.class.new(
          min_x: [@min_x, other.min_x].min,
          min_y: [@min_y, other.min_y].min,
          max_x: [@max_x, other.max_x].max,
          max_y: [@max_y, other.max_y].max,
        )
      end

      def <=>(other)
        return nil unless other.is_a?(Bounds)

        [@min_x, @min_y, @max_x, @max_y] <=>
          [other.min_x, other.min_y, other.max_x, other.max_y]
      end

      def hash
        [@min_x, @min_y, @max_x, @max_y].hash
      end
    end
  end
end
