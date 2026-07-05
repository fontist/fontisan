# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Propagates anchors from base glyphs to composite glyphs.
        #
        # In UFO sources, a composite glyph references base glyphs via
        # Component entries. Anchors (mark-attachment points used by
        # GPOS mark feature writers) typically live on the base glyphs
        # only — the composite inherits them by applying each
        # component's transformation matrix to the base's anchors.
        #
        # This filter does that propagation in place. After it runs,
        # every composite glyph carries its component-derived anchors,
        # ready for the mark feature writer to read.
        #
        # Single-pass (no recursive propagation through multi-level
        # component chains). Multi-level propagation would require
        # topological sort; if you need it, run the filter repeatedly
        # until no anchors change.
        module PropagateAnchors
          # @param glyphs [Array<Fontisan::Ufo::Glyph>] the glyphs to
          #   mutate. Must include any base glyphs referenced by
          #   components, or those references will be silently
          #   skipped.
          # @param font [Fontisan::Ufo::Font, nil] optional explicit
          #   font lookup. When provided, base glyphs are resolved
          #   via +font.glyph(name)+ instead of the +glyphs+ array,
          #   so composites can reference base glyphs that aren't in
          #   the +glyphs+ list.
          # @return [Array<Fontisan::Ufo::Glyph>] the same array,
          #   mutated in place
          def self.run(glyphs, font: nil, **_opts)
            lookup = build_lookup(font, glyphs)

            glyphs.each do |glyph|
              next if glyph.components.empty?

              glyph.components.each do |component|
                base = lookup[component.base_glyph]
                next unless base

                transform = coerce_transformation(component.transformation)
                propagate_anchors(glyph, base, transform)
              end
            end

            glyphs
          end

          class << self
            private

            def build_lookup(font, glyphs)
              return ->(name) { font.glyph(name) } if font

              hash = glyphs.to_h { |g| [g.name, g] }
              ->(name) { hash[name] }
            end

            def coerce_transformation(matrix)
              return Fontisan::Ufo::Transformation.new if matrix.nil?
              return matrix if matrix.is_a?(Fontisan::Ufo::Transformation)

              Fontisan::Ufo::Transformation.new(
                a: matrix[0], b: matrix[1],
                c: matrix[2], d: matrix[3],
                e: matrix[4], f: matrix[5]
              )
            end

            # Copy each anchor from +base+ into +glyph+, transformed
            # by +transform+. Skip anchors whose (name, transformed
            # x, transformed y) already exist on +glyph+ (the user
            # may have placed them manually). Coordinates are coerced
            # to Float so an Integer manual placement and the Float
            # transform output compare equal as dedup keys (Ruby's
            # eql? is type-strict, but == treats 100 == 100.0).
            def propagate_anchors(glyph, base, transform)
              existing = glyph.anchors.to_h do |a|
                [[a.name, a.x.to_f, a.y.to_f], true]
              end

              base.anchors.each do |anchor|
                tx, ty = transform.apply(anchor.x, anchor.y)
                key = [anchor.name, tx, ty]
                next if existing[key]

                glyph.add_anchor(Fontisan::Ufo::Anchor.new(
                                   x: tx, y: ty, name: anchor.name,
                                 ))
                existing[key] = true
              end
            end
          end
        end
      end
    end
  end
end
