# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Path
      # Mutable state carried through the contour-building walk.
      # Tracks the current pen position, the subpath start (for Z
      # closure), the last cubic and quadratic control points (for
      # smooth-curve reflection), and the contour being assembled.
      class State
        attr_reader :contours, :current, :subpath_start,
                    :cubic_control, :quad_control

        def initialize
          @contours = []
          @current = nil
          @subpath_start = nil
          @cubic_control = nil
          @quad_control = nil
          @pending = nil
        end

        # Start a new subpath at (x, y). Flushes any in-progress contour.
        def start_contour(x, y)
          finalize_contour
          @pending = []
          add_point(x, y, "line")
          @subpath_start = [x, y]
          @cubic_control = nil
          @quad_control = nil
        end

        # Append a point to the current contour and advance current position
        # for on-curve points (off-curve control points do not advance).
        def add_point(x, y, type)
          return unless @pending

          @pending << Fontisan::Ufo::Point.new(x: x, y: y, type: type)
          return if type == "offcurve"

          @current = [x, y]
        end

        # Mark the end of the current subpath. The contour is closed
        # implicitly (UFO contours wrap around). Reset current to the
        # subpath start so a subsequent M picks up from the right place.
        def close_contour
          return unless @pending

          finalize_contour
          @current = @subpath_start
        end

        # Flush the in-progress contour into the contours list if it
        # has more than one point (a lone M with nothing else is
        # degenerate and dropped).
        def finalize_contour
          return unless @pending

          @contours << Fontisan::Ufo::Contour.new(@pending) if @pending.size > 1
          @pending = nil
        end

        def cubic_control=(value)
          @cubic_control = value
        end

        def quad_control=(value)
          @quad_control = value
        end

        def reset_controls
          @cubic_control = nil
          @quad_control = nil
        end
      end
    end
  end
end
