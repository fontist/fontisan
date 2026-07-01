# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    # Geometry primitives for SvgToGlyf: affine transforms, SVG
    # transform attribute parsing, and coordinate normalization.
    module Geometry
      autoload :AffineTransform, "fontisan/svg_to_glyf/geometry/affine_transform"
      autoload :TransformParser, "fontisan/svg_to_glyf/geometry/transform_parser"
      autoload :Normalizer, "fontisan/svg_to_glyf/geometry/normalizer"
    end
  end
end
