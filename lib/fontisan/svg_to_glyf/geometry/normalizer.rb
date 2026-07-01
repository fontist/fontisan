# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Geometry
      # Computes the affine transform that maps SVG viewBox coordinates
      # (Y-down, origin at top-left) into font coordinates (Y-up, origin
      # at bottom-left, scaled to UPM).
      #
      # The normalization combines a Y-flip across the viewBox midline
      # with a uniform scale from viewBox units to font units. The
      # resulting matrix is then composed with the SVG document's
      # accumulated group transform to produce the final per-point
      # transform.
      class Normalizer
        attr_reader :viewbox_width, :viewbox_height, :upm

        # @param viewbox_width [Float] SVG viewBox width
        # @param viewbox_height [Float] SVG viewBox height
        # @param upm [Integer] font units-per-em
        def initialize(viewbox_width:, viewbox_height:, upm:)
          @viewbox_width = viewbox_width.to_f
          @viewbox_height = viewbox_height.to_f
          @upm = upm.to_f
        end

        # @return [AffineTransform] the viewBox→font normalization
        def matrix
          sx = @upm / @viewbox_width
          sy = @upm / @viewbox_height
          AffineTransform.new(sx, 0, 0, -sy, 0, @upm)
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
