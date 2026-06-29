# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Converts cubic Bezier curves to quadratic. TrueType outlines
        # only support quadratic Beziers; UFO sources typically use
        # cubic. This filter walks each contour, finds cubic segments
        # (two consecutive off-curve points followed by an on-curve),
        # and replaces them with one or more quadratic approximations.
        #
        # Algorithm (fontTools-compatible):
        #   For cubic (P0, C1, C2, P3):
        #     Q1 = (3*C1 - P0) / 2
        #     Q2 = (3*C2 - P3) / 2
        #     Q  = midpoint(Q1, Q2)
        #     Error ≈ |Q1 - Q2| / 3
        #     If error ≤ tolerance: emit one quadratic (P0, Q, P3)
        #     Else: subdivide at t=0.5, recurse each half.
        module CubicToQuadratic
          DEFAULT_TOLERANCE = 1.0

          # @param glyphs [Array<Fontisan::Ufo::Glyph>]
          # @param tolerance [Float] max deviation in font units
          # @return [Array<Fontisan::Ufo::Glyph>] the same array, mutated
          def self.run(glyphs, tolerance: DEFAULT_TOLERANCE, **_opts)
            glyphs.each do |glyph|
              glyph.contours.each_with_index do |contour, _ci|
                contour.points = convert_contour(contour.points, tolerance)
              end
            end
            glyphs
          end

          # Walk a contour's point list and replace cubic segments
          # with quadratic approximations. Preserves on-curve points
          # (lines, moves); only touches (off, off, on) triplets.
          #
          # @param points [Array<Fontisan::Ufo::Point>]
          # @param tolerance [Float]
          # @return [Array<Fontisan::Ufo::Point>] new point array
          def self.convert_contour(points, tolerance)
            return points if points.size < 4

            result = []
            i = 0

            while i < points.size
              # Check if we have a cubic segment: off, off, on-curve
              if i + 2 < points.size &&
                  off_curve?(points[i]) &&
                  off_curve?(points[i + 1]) &&
                  on_curve?(points[i + 2])
                # The previous on-curve point (P0) is the last on-curve
                # before this segment. If result is empty, use the last
                # point in the original contour (contour wraps around).
                p0 = result.empty? ? last_on_curve(points) : result.last

                if p0
                  c1 = points[i]
                  c2 = points[i + 1]
                  p3 = points[i + 2]

                  quads = subdivide_cubic(p0, c1, c2, p3, tolerance)
                  quads.each { |q| result << q }
                  i += 3
                else
                  result << points[i]
                  i += 1
                end
              else
                result << points[i]
                i += 1
              end
            end

            result
          end

          # Recursive cubic-to-quadratic subdivision.
          # Returns a list of Points: alternating off-curve control
          # points and on-curve endpoints.
          def self.subdivide_cubic(p0, c1, c2, p3, tolerance)
            q1x = (3.0 * c1.x - p0.x) / 2.0
            q1y = (3.0 * c1.y - p0.y) / 2.0
            q2x = (3.0 * c2.x - p3.x) / 2.0
            q2y = (3.0 * c2.y - p3.y) / 2.0

            # Error metric: half the distance between Q1 and Q2
            dx = (q1x - q2x).abs
            dy = (q1y - q2y).abs
            error = [dx, dy].max / 3.0

            if error <= tolerance
              # Single quadratic approximation
              mid_x = (q1x + q2x) / 2.0
              mid_y = (q1y + q2y) / 2.0
              [
                Point.new(x: mid_x, y: mid_y, type: "offcurve"),
                Point.new(x: p3.x, y: p3.y, type: p3.type, smooth: p3.smooth),
              ]
            else
              # Subdivide at t=0.5
              midpoint_on_cubic(p0, c1, c2, p3, 0.5)

              # Left half: P0, L1, L2, M
              Point.new(x: (p0.x + c1.x) / 2.0,
                        y: (p0.y + c1.y) / 2.0, type: "offcurve")
              Point.new(x: (c1.x + c2.x) / 4.0 + (p0.x + c1.x) / 4.0,
                        y: (c1.y + c2.y) / 4.0 + (p0.y + c1.y) / 4.0,
                        type: "offcurve")
              # Actually, proper De Casteljau subdivision:
              l1x = (p0.x + c1.x) / 2.0
              l1y = (p0.y + c1.y) / 2.0
              mx = (c1.x + c2.x) / 2.0
              my = (c1.y + c2.y) / 2.0
              r2x = (c2.x + p3.x) / 2.0
              r2y = (c2.y + p3.y) / 2.0
              l2x = (l1x + mx) / 2.0
              l2y = (l1y + my) / 2.0
              r1x = (mx + r2x) / 2.0
              r1y = (my + r2y) / 2.0
              mid_x = (l2x + r1x) / 2.0
              mid_y = (l2y + r1y) / 2.0

              left_p0 = p0
              left_c1 = Point.new(x: l1x, y: l1y, type: "offcurve")
              left_c2 = Point.new(x: l2x, y: l2y, type: "offcurve")
              left_p3 = Point.new(x: mid_x, y: mid_y, type: "qcurve")

              right_p0 = left_p3
              right_c1 = Point.new(x: r1x, y: r1y, type: "offcurve")
              right_c2 = Point.new(x: r2x, y: r2y, type: "offcurve")
              right_p3 = p3

              left = subdivide_cubic(left_p0, left_c1, left_c2, left_p3, tolerance)
              right = subdivide_cubic(right_p0, right_c1, right_c2, right_p3, tolerance)

              # Drop the duplicated midpoint point between halves
              left + right
            end
          end

          # Evaluate a point on a cubic Bezier at parameter t.
          def self.midpoint_on_cubic(p0, c1, c2, p3, t)
            mt = 1.0 - t
            x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x +
              3 * mt * t * t * c2.x + t * t * t * p3.x
            y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y +
              3 * mt * t * t * c2.y + t * t * t * p3.y
            Point.new(x: x, y: y, type: "qcurve")
          end

          def self.last_on_curve(points)
            points.reverse_each.find { |p| on_curve?(p) }
          end

          def self.on_curve?(point)
            ["line", "move", "curve", "qcurve"].include?(point.type)
          end

          def self.off_curve?(point)
            point.type == "offcurve"
          end

          private_class_method :convert_contour, :subdivide_cubic,
                               :midpoint_on_cubic, :last_on_curve,
                               :on_curve?, :off_curve?
        end
      end
    end
  end
end
