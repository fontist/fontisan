# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Geometry
      # Computes the affine transform that maps SVG coordinate space
      # (Y-down, arbitrary origin) into font coordinate space (Y-up,
      # origin at the bottom-left of the em-square, scaled to UPM).
      #
      # The normalization accepts a Ufo::Bounds describing the SVG
      # coordinate extent to map into the em-square. That bounds may
      # be the SVG viewBox, the actual content extents, or the union
      # of both — Assembler decides which.
      #
      # The transform is:
      #
      #   1. Translate the source origin (min_x, min_y) to (0, 0).
      #   2. Scale uniformly to font units: (upm/w, upm/h).
      #   3. Flip Y across the half-height of the scaled space.
      #   4. Translate up by upm so the top of the source maps to the
      #      top of the em-square.
      #
      # The resulting matrix is composed with the SVG document's
      # accumulated group transform to produce the final per-point
      # transform.
      class Normalizer
        attr_reader :bounds, :upm

        # @param bounds [Ufo::Bounds] source coordinate extents
        # @param upm [Integer, Float] font units-per-em
        def initialize(bounds:, upm:)
          @bounds = bounds
          @upm = upm.to_f
        end

        # @return [AffineTransform] the source→font normalization
        def matrix
          w = @bounds.width
          h = @bounds.height
          return AffineTransform.identity if w.zero? || h.zero?

          sx = @upm / w
          sy = @upm / h
          # x' = sx * (x - min_x)
          # y' = -sy * (y - min_y) + upm
          AffineTransform.new(sx, 0, 0, -sy,
                              -sx * @bounds.min_x,
                              sy * @bounds.min_y + @upm)
        end

        # Compose the normalization with an SVG group transform,
        # producing the final per-point transform.
        #
        # @param group_transform [AffineTransform] accumulated <g> transforms
        # @return [AffineTransform] final transform: font_point = N · T · path_point
        def final_transform(group_transform = AffineTransform.identity)
          matrix.compose(group_transform)
        end
      end
    end
  end
end
