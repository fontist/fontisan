# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Path
      # Measures the bounding box of an array of Ufo::Contour objects.
      #
      # SvgToGlyf's Normalizer scales coordinates using the SVG viewBox
      # dimensions. But SVG path data can have coordinates outside the
      # viewBox (valid SVG — they're just visually clipped). Without
      # measuring the actual contour bounds, those coordinates pass
      # through at the wrong scale, producing glyphs 2-11x too large.
      #
      # Bounds solves this by computing the real coordinate range from
      # the built contours. The Assembler uses Bounds to determine the
      # correct normalization dimensions.
      #
      class Bounds
        attr_reader :min_x, :min_y, :max_x, :max_y

        def initialize(min_x:, min_y:, max_x:, max_y:)
          @min_x = min_x.to_f
          @min_y = min_y.to_f
          @max_x = max_x.to_f
          @max_y = max_y.to_f
        end

        # @param contours [Array<Fontisan::Ufo::Contour>]
        # @return [Bounds]
        def self.measure(contours)
          points = contours.flat_map(&:points)
          return empty if points.empty?

          xs = points.map(&:x)
          ys = points.map(&:y)
          new(min_x: xs.min, min_y: ys.min, max_x: xs.max, max_y: ys.max)
        end

        # @return [Bounds] a zero-extent bounds at the origin
        def self.empty
          new(min_x: 0, min_y: 0, max_x: 0, max_y: 0)
        end

        def width
          max_x - min_x
        end

        def height
          max_y - min_y
        end

        def empty?
          width.zero? && height.zero?
        end
      end
    end
  end
end
