# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Geometry
      # A 2×3 affine transform representing:
      #
      #   x' = a·x + c·y + e
      #   y' = b·x + d·y + f
      #
      # Every coordinate operation in SvgToGlyf (SVG group transforms,
      # viewBox mapping, Y-flip, UPM scaling) is modeled as an
      # AffineTransform so they can be composed into a single matrix
      # applied once per point.
      class AffineTransform
        attr_reader :a, :b, :c, :d, :e, :f

        # @param a [Float] x-scale
        # @param b [Float] y-skew-x
        # @param c [Float] x-skew-y
        # @param d [Float] y-scale
        # @param e [Float] x-translate
        # @param f [Float] y-translate
        def initialize(a, b, c, d, e, f)
          @a = a.to_f
          @b = b.to_f
          @c = c.to_f
          @d = d.to_f
          @e = e.to_f
          @f = f.to_f
        end

        def self.identity
          new(1, 0, 0, 1, 0, 0)
        end

        def self.translate(tx, ty = 0)
          new(1, 0, 0, 1, tx, ty)
        end

        def self.scale(sx, sy = nil)
          sy = sx if sy.nil?
          new(sx, 0, 0, sy, 0, 0)
        end

        def self.rotate_radians(angle)
          cos = Math.cos(angle)
          sin = Math.sin(angle)
          new(cos, sin, -sin, cos, 0, 0)
        end

        def self.rotate_degrees(angle)
          rotate_radians(angle.to_f * Math::PI / 180.0)
        end

        def self.skew_x_radians(angle)
          new(1, 0, Math.tan(angle), 1, 0, 0)
        end

        def self.skew_y_radians(angle)
          new(1, Math.tan(angle), 0, 1, 0, 0)
        end

        # Reflect across a horizontal line at y = axis.
        # Points above the axis map below it and vice versa.
        def self.flip_y(axis)
          new(1, 0, 0, -1, 0, 2 * axis)
        end

        # Compose this transform with `other`, returning a new
        # AffineTransform equivalent to applying `other` first,
        # then `self`. This matches SVG's `transform="self other"`
        # convention.
        #
        #   result.apply(x, y) == self.apply(*other.apply(x, y))
        def compose(other)
          AffineTransform.new(
            @a * other.a + @c * other.b,
            @b * other.a + @d * other.b,
            @a * other.c + @c * other.d,
            @b * other.c + @d * other.d,
            @a * other.e + @c * other.f + @e,
            @b * other.e + @d * other.f + @f,
          )
        end

        # @param x [Numeric]
        # @param y [Numeric]
        # @return [Array(Float, Float)] transformed [x', y']
        def apply(x, y)
          [@a * x + @c * y + @e, @b * x + @d * y + @f]
        end

        def identity?
          @a == 1 && @b.zero? && @c.zero? && @d == 1 && @e.zero? && @f.zero?
        end

        def ==(other)
          other.is_a?(AffineTransform) &&
            @a == other.a && @b == other.b && @c == other.c &&
            @d == other.d && @e == other.e && @f == other.f
        end

        alias eql? ==

        def hash
          [@a, @b, @c, @d, @e, @f].hash
        end
      end
    end
  end
end
