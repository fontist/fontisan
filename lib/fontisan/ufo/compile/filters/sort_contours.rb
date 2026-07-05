# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Sorts the contours within each glyph + the points within
        # each contour. Two distinct operations, both required for
        # TrueType hinting compatibility:
        #
        # 1. **Start-point alignment**: rotate each contour's point
        #    list so an on-curve point is first (TrueType hinting
        #    programs expect this).
        #
        # 2. **Contour ordering**: order contours within each glyph
        #    by their starting point's (Y descending, X ascending)
        #    so the hint program processes outer contours before
        #    inner ones (true-type convention for nested shapes).
        #
        # This is the fontTools/ufo2ft sort_contours filter, scoped
        # to the contour-level concerns. Per-glyph sort across
        # multiple glyphs is the caller's responsibility (callers
        # typically sort glyphs by gid / post name).
        module SortContours
          # @param glyphs [Array<Fontisan::Ufo::Glyph>]
          # @return [Array<Fontisan::Ufo::Glyph>] the same array,
          #   mutated in place
          def self.run(glyphs, **_opts)
            glyphs.each do |glyph|
              glyph.contours.each { |c| rotate_to_first_on_curve(c) }
              glyph.contours.sort_by! { |c| sort_key(c) }
            end
            glyphs
          end

          class << self
            private

            # Rotate the point list so an on-curve point sits at
            # index 0. If the contour is all off-curve (impossible
            # for valid UFO but defensively handled), leave it
            # unchanged.
            def rotate_to_first_on_curve(contour)
              points = contour.points
              return if points.empty?
              return if points.first.on_curve?

              first_on = points.find_index(&:on_curve?)
              return unless first_on

              contour.points = points.rotate(first_on)
            end

            # Sort key: descending Y (outer contours typically start
            # at the top), then ascending X (leftmost first when Y
            # ties). Uses the first on-curve point's coordinates.
            # Empty contours sort last (Float::INFINITY).
            def sort_key(contour)
              first = contour.points.find(&:on_curve?) || contour.points.first
              return [Float::INFINITY, Float::INFINITY] unless first

              [-first.y.to_f, first.x.to_f]
            end
          end
        end
      end
    end
  end
end
