# frozen_string_literal: true

module Fontisan
  module Ufo
    # 2×3 transformation matrix, as used in UFO 3 for component and
    # image placement. The matrix is laid out in the standard affine
    # row-major order: `[a b c d e f]` represents
    #
    #     | a c e |
    #     | b d f |
    #     | 0 0 1 |
    #
    # (UFO and OpenType both use the row-major convention despite the
    # geometrically column-major appearance — this is how the
    # `transformation` element reads in .glif XML.)
    class Transformation
      IDENTITY_MATRIX = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0].freeze

      attr_reader :a, :b, :c, :d, :e, :f

      def initialize(a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0)
        @a = a.to_f
        @b = b.to_f
        @c = c.to_f
        @d = d.to_f
        @e = e.to_f
        @f = f.to_f
      end

      def identity?
        [a, b, c, d, e, f] == IDENTITY_MATRIX
      end

      def to_a
        [a, b, c, d, e, f]
      end
    end
  end
end
