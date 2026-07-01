# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Path
      # Converts an array of Path::Command objects into an array of
      # Fontisan::Ufo::Contour objects.
      #
      # Tracks current-point, subpath-start, and previous-control-point
      # state to resolve relative coordinates and smooth-curve reflections.
      #
      # Point type mapping (Ufo::Point types):
      #   M (first in subpath) → first point of contour, type "line"
      #   L / H / V            → "line"
      #   C                    → "offcurve", "offcurve", "curve"
      #   S                    → reflected "offcurve", "offcurve", "curve"
      #   Q                    → "offcurve", "qcurve"
      #   T                    → reflected "offcurve", "qcurve"
      #   Z                    → closes the contour (no point emitted)
      class ContourBuilder
        # @param commands [Array<Path::Command>]
        # @return [Array<Fontisan::Ufo::Contour>]
        def build(commands)
          state = State.new
          commands.each { |cmd| apply(cmd, state) }
          state.finalize_contour
          state.contours
        end

        private

        def apply(cmd, state)
          case cmd.type
          when :M then handle_move(cmd, state)
          when :L then handle_line(cmd, state)
          when :H then handle_horizontal(cmd, state)
          when :V then handle_vertical(cmd, state)
          when :C then handle_cubic(cmd, state)
          when :S then handle_smooth_cubic(cmd, state)
          when :Q then handle_quadratic(cmd, state)
          when :T then handle_smooth_quadratic(cmd, state)
          when :Z then state.close_contour
          end
        end

        def handle_move(cmd, state)
          x, y = resolve_pair(cmd, state.current)
          state.start_contour(x, y)
        end

        def handle_line(cmd, state)
          x, y = resolve_pair(cmd, state.current)
          state.add_point(x, y, "line")
          state.reset_controls
        end

        def handle_horizontal(cmd, state)
          dx = cmd.absolute ? cmd.args[0] - state.current[0] : cmd.args[0]
          x = state.current[0] + dx
          y = state.current[1]
          state.add_point(x, y, "line")
          state.reset_controls
        end

        def handle_vertical(cmd, state)
          dy = cmd.absolute ? cmd.args[0] - state.current[1] : cmd.args[0]
          x = state.current[0]
          y = state.current[1] + dy
          state.add_point(x, y, "line")
          state.reset_controls
        end

        def handle_cubic(cmd, state)
          base = state.current
          c1 = resolve_pair_at(cmd, base, 0)
          c2 = resolve_pair_at(cmd, base, 2)
          endpoint = resolve_pair_at(cmd, base, 4)

          state.add_point(c1[0], c1[1], "offcurve")
          state.add_point(c2[0], c2[1], "offcurve")
          state.add_point(endpoint[0], endpoint[1], "curve")
          state.cubic_control = c2
        end

        def handle_smooth_cubic(cmd, state)
          base = state.current
          reflected = reflect(state.cubic_control, base)
          c2 = resolve_pair_at(cmd, base, 0)
          endpoint = resolve_pair_at(cmd, base, 2)

          state.add_point(reflected[0], reflected[1], "offcurve")
          state.add_point(c2[0], c2[1], "offcurve")
          state.add_point(endpoint[0], endpoint[1], "curve")
          state.cubic_control = c2
        end

        def handle_quadratic(cmd, state)
          base = state.current
          control = resolve_pair_at(cmd, base, 0)
          endpoint = resolve_pair_at(cmd, base, 2)

          state.add_point(control[0], control[1], "offcurve")
          state.add_point(endpoint[0], endpoint[1], "qcurve")
          state.quad_control = control
        end

        def handle_smooth_quadratic(cmd, state)
          base = state.current
          reflected = reflect(state.quad_control, base)
          endpoint = resolve_pair_at(cmd, base, 0)

          state.add_point(reflected[0], reflected[1], "offcurve")
          state.add_point(endpoint[0], endpoint[1], "qcurve")
          state.quad_control = reflected
        end

        # Resolve an (x,y) pair from a command at the given arg offset.
        # Absolute: use args directly. Relative: add to base point.
        def resolve_pair_at(cmd, base, offset)
          if cmd.absolute
            [cmd.args[offset], cmd.args[offset + 1]]
          else
            [base[0] + cmd.args[offset], base[1] + cmd.args[offset + 1]]
          end
        end

        def resolve_pair(cmd, base)
          resolve_pair_at(cmd, base, 0)
        end

        # Reflect a control point through the current point.
        def reflect(control, current)
          return current unless control

          [2 * current[0] - control[0], 2 * current[1] - control[1]]
        end
      end
    end
  end
end
