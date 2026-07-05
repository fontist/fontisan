# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Boolean union of overlapping contours within each glyph.
        # Two contours that overlap visually are merged into one,
        # removing the seam. Required for some hinting programs and
        # for SVG/COLR rendering correctness.
        #
        # == Why bounding-box approximation, not polygon clipping
        #
        # Full polygon clipping (Greiner-Hormann or Vatti) operates
        # on straight-line polygons. UFO contours are Bezier curves.
        # Applying polygon clipping would require:
        #   1. Flatten Bezier to polygon edges (tessellation).
        #   2. Run polygon clipping (union).
        #   3. Re-fit Bezier curves on the result (curve fitting).
        #
        # Step 3 is the killer: curve fitting is lossy. The output
        # curves won't match the input curves' control points,
        # changing the glyph's rendering at small sizes. For a font
        # pipeline, preserving curve fidelity matters more than
        # mathematical union correctness.
        #
        # The bounding-box approximation handles the common cases
        # (overlapping duplicates, fully-contained sub-contours)
        # without losing any curve data. It does NOT handle partial
        # overlaps — those remain as separate contours. For fonts
        # that need partial-overlap removal, preprocess in an editor
        # (FontLab, Glyphs) or use the `clipper` gem as a pre-compile
        # step with explicit curve-flattening tolerances.
        module RemoveOverlaps
          # @param glyphs [Array<Fontisan::Ufo::Glyph>]
          # @return [Array<Fontisan::Ufo::Glyph>] the same array,
          #   mutated in place
          def self.run(glyphs, **_opts)
            glyphs.each { |g| remove_overlaps_in_glyph(g) }
            glyphs
          end

          class << self
            private

            def remove_overlaps_in_glyph(glyph)
              return if glyph.contours.size < 2

              bboxes = glyph.contours.map { |c| bounding_box(c) }
              drop = Set.new

              glyph.contours.each_with_index do |outer, i|
                next if drop.include?(i)

                glyph.contours.each_with_index do |inner, j|
                  next if i == j || drop.include?(j)

                  # Drop inner when its bbox is fully inside outer's.
                  if contained_in?(bboxes[j], bboxes[i]) && (inner.points.size <= outer.points.size)
                    # Sanity: only drop if the point count is smaller —
                    # a fully-contained contour with MORE points is
                    # almost certainly the outer one in a malformed
                    # source, and dropping it would lose data.
                    drop << j
                  end
                end
              end

              return if drop.empty?

              glyph.contours.reject!.with_index { |_c, i| drop.include?(i) }
            end

            def bounding_box(contour)
              points = contour.points
              return { x_min: 0, y_min: 0, x_max: 0, y_max: 0 } if points.empty?

              xs = points.map(&:x)
              ys = points.map(&:y)
              { x_min: xs.min, y_min: ys.min, x_max: xs.max, y_max: ys.max }
            end

            def contained_in?(inner, outer)
              inner[:x_min] >= outer[:x_min] &&
                inner[:x_max] <= outer[:x_max] &&
                inner[:y_min] >= outer[:y_min] &&
                inner[:y_max] <= outer[:y_max]
            end
          end
        end
      end
    end
  end
end
