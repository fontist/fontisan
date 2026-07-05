# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Applies a 2×3 affine transformation to every glyph's
        # contours + components. The general-purpose filter — other
        # filters (decompose_components, propagate_anchors) are
        # special cases of geometric transforms applied to specific
        # glyph subsets.
        #
        # Used for:
        #   - Symmetric mirroring (e.g. italic→upright flip).
        #   - Slant adjustment.
        #   - Custom per-font offsets that callers want baked in at
        #     compile time rather than carried as variation axis deltas.
        #
        # Identity matrix is a no-op fast path.
        module Transformations
          DEFAULT_OFFSET_X = 0.0
          DEFAULT_OFFSET_Y = 0.0

          # @param glyphs [Array<Fontisan::Ufo::Glyph>]
          # @param matrix [Fontisan::Ufo::Transformation, Array<Numeric>, nil]
          #   The affine matrix to apply. Accepts either a
          #   +Transformation+ value object or the raw +[a, b, c, d, e, f]+
          #   array. +nil+ (the default) is a no-op — leaves glyphs
          #   unchanged.
          # @return [Array<Fontisan::Ufo::Glyph>] the same array (mutated)
          def self.run(glyphs, matrix: nil, **_opts)
            return glyphs if matrix.nil?

            transform = coerce_transformation(matrix)
            return glyphs if transform.identity?

            glyphs.each { |g| apply_to_glyph(g, transform) }
            glyphs
          end

          class << self
            private

            # Coerce the matrix argument into a Transformation.
            # Centralizes the "array, object, or nil?" decision so
            # callers can pass any form.
            def coerce_transformation(matrix)
              return Fontisan::Ufo::Transformation.new if matrix.nil?
              return matrix if matrix.is_a?(Fontisan::Ufo::Transformation)

              Fontisan::Ufo::Transformation.new(
                a: matrix[0], b: matrix[1],
                c: matrix[2], d: matrix[3],
                e: matrix[4], f: matrix[5]
              )
            end

            # Apply the transform in place: each contour's points are
            # rewritten with transformed coordinates; each component's
            # +transformation+ is composed with the new one (so nested
            # component refs chain correctly).
            def apply_to_glyph(glyph, transform)
              glyph.contours.each do |contour|
                contour.points = contour.points.map do |pt|
                  tx, ty = transform.apply(pt.x, pt.y)
                  Fontisan::Ufo::Point.new(
                    x: tx, y: ty,
                    type: pt.type, smooth: pt.smooth
                  )
                end
              end

              glyph.components.map! do |component|
                Fontisan::Ufo::Component.new(
                  base_glyph: component.base_glyph,
                  # Composition order: outer transform ∘ existing.
                  # For a base-glyph point P, the component places it
                  # at T_existing(P) in this glyph; the outer transform
                  # then maps that to T_outer(T_existing(P)). So the
                  # new component transformation is T_outer ∘ T_existing.
                  transformation: compose(transform, component.transformation),
                  identifier: component.identifier,
                )
              end
            end

            # Compose two affine transformations: result = outer ∘ inner
            #   | outer.a outer.c outer.e |   | inner.a inner.c inner.e |
            #   | outer.b outer.d outer.f | × | inner.b inner.d inner.f |
            #   |   0        0        1   |   |   0        0        1   |
            #
            # Each input can be a Transformation, a 6-array, or nil
            # (treated as identity — the default Component state).
            # The result is always a Transformation.
            def compose(outer, inner)
              outer_t = coerce_transformation(outer)
              inner_t = coerce_transformation(inner)

              Fontisan::Ufo::Transformation.new(
                a: outer_t.a * inner_t.a + outer_t.c * inner_t.b,
                b: outer_t.b * inner_t.a + outer_t.d * inner_t.b,
                c: outer_t.a * inner_t.c + outer_t.c * inner_t.d,
                d: outer_t.b * inner_t.c + outer_t.d * inner_t.d,
                e: outer_t.a * inner_t.e + outer_t.c * inner_t.f + outer_t.e,
                f: outer_t.b * inner_t.e + outer_t.d * inner_t.f + outer_t.f,
              )
            end
          end
        end
      end
    end
  end
end
