# frozen_string_literal: true

module Fontisan
  module Tables
    # Converts between quadratic and cubic Bézier curves
    #
    # This class provides bidirectional conversion between TrueType's
    # quadratic Bézier curves and CFF's cubic Bézier curves.
    #
    # **Quadratic → Cubic (Exact)**:
    # Uses degree elevation formula to convert a quadratic Bézier curve
    # into an equivalent cubic Bézier curve with 100% accuracy.
    #
    # **Cubic → Quadratic (Approximation)**:
    # Uses adaptive subdivision to approximate a cubic Bézier curve with
    # one or more quadratic curves, maintaining error within tolerance.
    #
    # @example Converting quadratic to cubic
    #   quad = { x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }
    #   cubic = CurveConverter.quadratic_to_cubic(quad)
    #   # => { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
    #
    # @example Converting cubic to quadratic
    #   cubic = { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
    #   quads = CurveConverter.cubic_to_quadratic(cubic, max_error: 0.5)
    #   # => [{ x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }]
    class CurveConverter
      # Default maximum error tolerance in font units
      DEFAULT_MAX_ERROR = 0.5

      # Number of samples for error measurement
      ERROR_SAMPLE_COUNT = 11

      # Convert quadratic Bézier to cubic (exact conversion)
      #
      # Uses degree elevation formula to convert a quadratic Bézier curve
      # into an equivalent cubic Bézier curve. This conversion is exact
      # with 100% accuracy.
      #
      # Formula:
      # - CP0 = P0 (start point unchanged)
      # - CP1 = P0 + 2/3 * (P1 - P0)
      # - CP2 = P2 + 2/3 * (P1 - P2)
      # - CP3 = P2 (end point unchanged)
      #
      # @param quad [Hash] Quadratic curve {:x0, :y0, :x1, :y1, :x2, :y2}
      # @return [Hash] Cubic curve {:x0, :y0, :x1, :y1, :x2, :y2, :x3, :y3}
      # @raise [ArgumentError] If quad is invalid
      def self.quadratic_to_cubic(quad)
        validate_quadratic_curve!(quad)

        # P0 = start point
        # P1 = control point
        # P2 = end point
        x0 = quad[:x0]
        y0 = quad[:y0]
        x1 = quad[:x1]
        y1 = quad[:y1]
        x2 = quad[:x2]
        y2 = quad[:y2]

        # Degree elevation formula
        # CP1 = P0 + (2/3) * (P1 - P0)
        cx1 = x0 + (2.0 / 3.0) * (x1 - x0)
        cy1 = y0 + (2.0 / 3.0) * (y1 - y0)

        # CP2 = P2 + (2/3) * (P1 - P2)
        cx2 = x2 + (2.0 / 3.0) * (x1 - x2)
        cy2 = y2 + (2.0 / 3.0) * (y1 - y2)

        {
          x0: x0,
          y0: y0,
          x1: cx1,
          y1: cy1,
          x2: cx2,
          y2: cy2,
          x3: x2,
          y3: y2,
        }
      end

      # Convert cubic Bézier to quadratic approximation
      #
      # Uses adaptive subdivision to approximate a cubic Bézier curve
      # with one or more quadratic curves. The algorithm recursively
      # subdivides the curve until the error is within tolerance.
      #
      # @param cubic [Hash] Cubic curve {:x0, :y0, :x1, :y1, :x2, :y2, :x3, :y3}
      # @param max_error [Float] Maximum error tolerance (default: 0.5 units)
      # @return [Array<Hash>] Array of quadratic curves
      # @raise [ArgumentError] If parameters are invalid
      def self.cubic_to_quadratic(cubic, max_error: DEFAULT_MAX_ERROR)
        validate_cubic_curve!(cubic)
        validate_max_error!(max_error)

        # Try to approximate with a single quadratic curve
        quad = approximate_cubic_with_quadratic(cubic)
        error = calculate_error(cubic, [quad])

        if error <= max_error
          [quad]
        else
          # Subdivide and recursively approximate
          left, right = subdivide_cubic(cubic, 0.5)
          cubic_to_quadratic(left, max_error: max_error) +
            cubic_to_quadratic(right, max_error: max_error)
        end
      end

      # Calculate maximum error between cubic and quadratic curves
      #
      # Samples points along the curves and measures the maximum
      # perpendicular distance between them.
      #
      # @param cubic [Hash] Original cubic curve
      # @param quadratics [Array<Hash>] Approximating quadratic curves
      # @return [Float] Maximum error distance
      # @raise [ArgumentError] If parameters are invalid
      def self.calculate_error(cubic, quadratics)
        validate_cubic_curve!(cubic)
        unless quadratics.is_a?(Array)
          raise ArgumentError,
                "quadratics must be Array"
        end
        raise ArgumentError, "quadratics cannot be empty" if quadratics.empty?

        max_error = 0.0

        # Sample points along the cubic curve
        ERROR_SAMPLE_COUNT.times do |i|
          t = i / (ERROR_SAMPLE_COUNT - 1.0)
          cubic_point = evaluate_cubic(cubic, t)

          # Find corresponding point on quadratic curves
          quad_point = find_point_on_quadratics(quadratics, t)

          # Calculate distance
          dx = cubic_point[:x] - quad_point[:x]
          dy = cubic_point[:y] - quad_point[:y]
          distance = Math.sqrt(dx * dx + dy * dy)

          max_error = distance if distance > max_error
        end

        max_error
      end

      # Subdivide cubic curve at parameter t using De Casteljau's algorithm
      #
      # @param cubic [Hash] Cubic curve to subdivide
      # @param t [Float] Parameter value (0.0 to 1.0)
      # @return [Array<Hash, Hash>] [left_curve, right_curve]
      def self.subdivide_cubic(cubic, t)
        validate_cubic_curve!(cubic)

        x0 = cubic[:x0]
        y0 = cubic[:y0]
        x1 = cubic[:x1]
        y1 = cubic[:y1]
        x2 = cubic[:x2]
        y2 = cubic[:y2]
        x3 = cubic[:x3]
        y3 = cubic[:y3]

        # De Casteljau's algorithm
        # First level
        q0x = lerp(x0, x1, t)
        q0y = lerp(y0, y1, t)
        q1x = lerp(x1, x2, t)
        q1y = lerp(y1, y2, t)
        q2x = lerp(x2, x3, t)
        q2y = lerp(y2, y3, t)

        # Second level
        r0x = lerp(q0x, q1x, t)
        r0y = lerp(q0y, q1y, t)
        r1x = lerp(q1x, q2x, t)
        r1y = lerp(q1y, q2y, t)

        # Third level (subdivision point)
        sx = lerp(r0x, r1x, t)
        sy = lerp(r0y, r1y, t)

        left = {
          x0: x0, y0: y0,
          x1: q0x, y1: q0y,
          x2: r0x, y2: r0y,
          x3: sx, y3: sy
        }

        right = {
          x0: sx, y0: sy,
          x1: r1x, y1: r1y,
          x2: q2x, y2: q2y,
          x3: x3, y3: y3
        }

        [left, right]
      end

      # Evaluate cubic Bézier curve at parameter t
      #
      # @param cubic [Hash] Cubic curve
      # @param t [Float] Parameter (0.0 to 1.0)
      # @return [Hash] Point {:x, :y}
      def self.evaluate_cubic(cubic, t)
        x0 = cubic[:x0]
        y0 = cubic[:y0]
        x1 = cubic[:x1]
        y1 = cubic[:y1]
        x2 = cubic[:x2]
        y2 = cubic[:y2]
        x3 = cubic[:x3]
        y3 = cubic[:y3]

        # Cubic Bézier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
        t2 = t * t
        t3 = t2 * t
        mt = 1.0 - t
        mt2 = mt * mt
        mt3 = mt2 * mt

        x = mt3 * x0 + 3.0 * mt2 * t * x1 + 3.0 * mt * t2 * x2 + t3 * x3
        y = mt3 * y0 + 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3 * y3

        { x: x, y: y }
      end

      # Evaluate quadratic Bézier curve at parameter t
      #
      # @param quad [Hash] Quadratic curve
      # @param t [Float] Parameter (0.0 to 1.0)
      # @return [Hash] Point {:x, :y}
      def self.evaluate_quadratic(quad, t)
        x0 = quad[:x0]
        y0 = quad[:y0]
        x1 = quad[:x1]
        y1 = quad[:y1]
        x2 = quad[:x2]
        y2 = quad[:y2]

        # Quadratic Bézier formula: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
        t2 = t * t
        mt = 1.0 - t
        mt2 = mt * mt

        x = mt2 * x0 + 2.0 * mt * t * x1 + t2 * x2
        y = mt2 * y0 + 2.0 * mt * t * y1 + t2 * y2

        { x: x, y: y }
      end

      private_class_method def self.approximate_cubic_with_quadratic(cubic)
        validate_cubic_curve!(cubic)

        x0 = cubic[:x0]
        y0 = cubic[:y0]
        x1 = cubic[:x1]
        y1 = cubic[:y1]
        x2 = cubic[:x2]
        y2 = cubic[:y2]
        x3 = cubic[:x3]
        y3 = cubic[:y3]

        # Better approximation: use weighted average that considers derivatives
        # For optimal approximation, we want to match the curve shape
        # Using the formula: C = 3/4*P1 + 3/4*P2 - 1/4*P0 - 1/4*P3
        # This minimizes the maximum error for most curves
        cx = 0.75 * x1 + 0.75 * x2 - 0.25 * x0 - 0.25 * x3
        cy = 0.75 * y1 + 0.75 * y2 - 0.25 * y0 - 0.25 * y3

        {
          x0: x0,
          y0: y0,
          x1: cx,
          y1: cy,
          x2: x3,
          y2: y3,
        }
      end

      private_class_method def self.find_point_on_quadratics(quadratics, t)
        # Determine which quadratic segment contains parameter t
        segment_count = quadratics.length
        segment_t = t * segment_count
        segment_index = [segment_t.floor, segment_count - 1].min
        local_t = segment_t - segment_index

        evaluate_quadratic(quadratics[segment_index], local_t)
      end

      private_class_method def self.lerp(a, b, t)
        a + t * (b - a)
      end

      private_class_method def self.validate_quadratic_curve!(quad)
        unless quad.is_a?(Hash)
          raise ArgumentError, "quad must be Hash, got: #{quad.class}"
        end

        required = %i[x0 y0 x1 y1 x2 y2]
        missing = required - quad.keys
        unless missing.empty?
          raise ArgumentError, "quad missing keys: #{missing.join(', ')}"
        end

        required.each do |key|
          value = quad[key]
          unless value.is_a?(Numeric)
            raise ArgumentError,
                  "quad[:#{key}] must be Numeric, got: #{value.class}"
          end
        end
      end

      private_class_method def self.validate_cubic_curve!(cubic)
        unless cubic.is_a?(Hash)
          raise ArgumentError, "cubic must be Hash, got: #{cubic.class}"
        end

        required = %i[x0 y0 x1 y1 x2 y2 x3 y3]
        missing = required - cubic.keys
        unless missing.empty?
          raise ArgumentError, "cubic missing keys: #{missing.join(', ')}"
        end

        required.each do |key|
          value = cubic[key]
          unless value.is_a?(Numeric)
            raise ArgumentError,
                  "cubic[:#{key}] must be Numeric, got: #{value.class}"
          end
        end
      end

      private_class_method def self.validate_max_error!(max_error)
        unless max_error.is_a?(Numeric)
          raise ArgumentError,
                "max_error must be Numeric, got: #{max_error.class}"
        end

        if max_error <= 0
          raise ArgumentError, "max_error must be positive, got: #{max_error}"
        end
      end
    end
  end
end
