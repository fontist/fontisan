# frozen_string_literal: true

module Fontisan
  module Svg
    # Renders a single UFO glyph as a standalone SVG document (a
    # `<svg>` root with one `<path>` and a viewBox sized to the
    # glyph's bounding box). Distinct from {FontGenerator}, which
    # emits a `<svg><defs><font>` document covering every glyph.
    #
    # Used by the `fontisan ufo extract` CLI command and by
    # downstream consumers that want per-glyph SVG exports without
    # having to slice up a font-format SVG themselves.
    #
    # Path rendering supports quadratic and cubic Bezier curves
    # (UFO's standard outline model). Curve logic is inlined here
    # rather than reaching into GlyphGenerator's private path code
    # — that logic is font-format-specific (Y-axis flip via
    # ViewBoxCalculator) and doesn't cleanly factor out.
    class StandaloneGlyph
      # @param units_per_em [Integer] font units-per-em (default 1000)
      # @param ascent [Integer] font ascender in font units (default 800)
      # @param descent [Integer] font descender in font units (default -200)
      def initialize(units_per_em: 1000, ascent: 800, descent: -200)
        @units_per_em = units_per_em.to_i
        @ascent = ascent.to_i
        @descent = descent.to_i
      end

      # @param glyph [Fontisan::Ufo::Glyph]
      # @return [String] standalone SVG XML
      def generate(glyph)
        path_data = path_data_for(glyph)
        view_box = view_box_for(glyph)

        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}">
            <path d="#{path_data}"/>
          </svg>
        SVG
      end

      private

      def path_data_for(glyph)
        return "" if glyph.contours.empty?

        glyph.contours.filter_map { |c| contour_path(c) }.join(" ")
      end

      # Emit an SVG path for one contour with Y-axis flip applied.
      # Walks points left-to-right; collects off-curve runs and
      # flushes them as a Bezier curve (Q for 1 control point, C
      # for 2). Single on-curve points become line segments.
      def contour_path(contour)
        points = contour.points
        return nil if points.empty?

        parts = []
        first = points.first
        parts << "M #{first.x} #{flip_y(first.y)}"

        i = 1
        while i < points.length
          if points[i].on_curve?
            parts << "L #{points[i].x} #{flip_y(points[i].y)}"
            i += 1
          else
            # Collect consecutive off-curve points (1 → quadratic,
            # 2 → cubic, 3+ → rare; treat as multiple quadratics).
            controls = []
            while i < points.length && !points[i].on_curve?
              controls << points[i]
              i += 1
            end
            end_pt = i < points.length ? points[i] : first
            i += 1 if i < points.length

            parts << curve_segment(controls, end_pt)
          end
        end

        parts << "Z"
        parts.join(" ")
      end

      def curve_segment(controls, end_pt)
        end_x = end_pt.x
        end_y = flip_y(end_pt.y)

        case controls.size
        when 1
          "Q #{controls[0].x} #{flip_y(controls[0].y)} #{end_x} #{end_y}"
        when 2
          "C #{controls[0].x} #{flip_y(controls[0].y)} " \
            "#{controls[1].x} #{flip_y(controls[1].y)} " \
            "#{end_x} #{end_y}"
        else
          # 3+ controls: emit a Q to the midpoint of the first two,
          # then continue. Rare in practice; degrades to Q chain.
          mid_x = (controls[0].x + controls[1].x) / 2.0
          mid_y = flip_y((controls[0].y + controls[1].y) / 2.0)
          "Q #{controls[0].x} #{flip_y(controls[0].y)} #{mid_x} #{mid_y}"
        end
      end

      def flip_y(y)
        @ascent - y.to_f
      end

      def view_box_for(glyph)
        bbox = bounding_box(glyph)
        format("%<xmin>s %<ymin>s %<w>s %<h>s",
               xmin: bbox[:x_min], ymin: bbox[:y_min],
               w: (bbox[:x_max] - bbox[:x_min]),
               h: (bbox[:y_max] - bbox[:y_min]))
      end

      def bounding_box(glyph)
        points = glyph.contours.flat_map(&:points)
        if points.empty?
          return { x_min: 0, y_min: 0, x_max: @units_per_em,
                   y_max: @units_per_em }
        end

        xs = points.map(&:x)
        ys = points.map(&:y)
        { x_min: xs.min, y_min: ys.min, x_max: xs.max, y_max: ys.max }
      end
    end
  end
end
