# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff
      # CFF2 CharStringBuilder — extends the CFF1 charstring with
      # variable-font operators (vsindex, blend).
      #
      # In CFF2, the hmoveto operator (22) is repurposed as vsindex
      # (selects a VariationStore item), and a new blend operator
      # (23) applies variation deltas to the current operands.
      #
      # The blend protocol for a single coordinate:
      #   push base_value, push delta_r0, ..., push delta_r(n-1), push 1, blend
      # After blend, the stack has one blended value.
      #
      # For n coordinates batched together:
      #   push base_0 + deltas_0, push base_1 + deltas_1, ..., push n, blend
      # After blend, the stack has n blended values.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2#charstring-operators
      class Cff2CharStringBuilder < CharStringBuilder
        # CFF2 replaces hmoveto(22) with vsindex(22). The :hmoveto key
        # is omitted entirely so attempts to emit it raise naturally.
        OPERATORS_CFF2 = OPERATORS.except(:hmoveto).merge(
          vsindex: 22,
          blend: 23,
        )

        # Tracks per-master current position during variable encoding.
        MasterState = Struct.new(:current_x, :current_y, keyword_init: true)

        # Build a complete variable CFF2 charstring from a default outline
        # plus variation master outlines.
        #
        # @param outline [Models::Outline] default-master outline
        # @param master_outlines [Array<Models::Outline>] one per region
        # @param num_regions [Integer] number of variation regions
        # @param width [Integer, nil] advance width
        # @return [String] CFF2 charstring bytes with blend sequences
        def self.build_variable(outline, master_outlines:, num_regions:, width: nil)
          new.build_variable_outline(outline, master_outlines, num_regions, width)
        end

        # ---------- variable-font encoding ----------

        # Build a variable charstring from a default outline + masters.
        # Creates the output buffer internally (same pattern as the
        # parent's build method).
        # @return [String] charstring bytes with blend sequences
        def build_variable_outline(outline, master_outlines, num_regions, width)
          @output = StringIO.new("".b)
          @first_move = true
          @current_x = 0.0
          @current_y = 0.0

          encode_width(width) if width
          encode_variable_outline(outline, master_outlines, num_regions)
          write_operator(:endchar)

          @output.string
        end

        # Process an outline with blend operators for each varying coordinate.
        def encode_variable_outline(outline, master_outlines, num_regions)
          @master_states = master_outlines.map { MasterState.new(current_x: 0, current_y: 0) }
          @num_regions = num_regions
          @has_blend = false

          outline.commands.each_with_index do |cmd, i|
            master_cmds = master_outlines.map { |mo| mo.commands[i] }
            encode_variable_command(cmd, master_cmds)
          end

          # Emit vsindex(0) at the start if any blend operators were used.
          # In a full implementation, vsindex selects the ItemVariationData
          # subtable; for single-subtable fonts, vsindex 0 is the default.
        end

        def encode_variable_command(cmd, master_cmds)
          case cmd[:type]
          when :move_to then encode_variable_moveto(cmd, master_cmds)
          when :line_to then encode_variable_lineto(cmd, master_cmds)
          when :curve_to then encode_variable_curveto(cmd, master_cmds)
          end
        end

        # ---------- variable moveto ----------

        def encode_variable_moveto(cmd, master_cmds)
          dx, dy, dx_deltas, dy_deltas = compute_variable_deltas(cmd, master_cmds)

          write_variable_number(dx, dx_deltas)
          write_variable_number(dy, dy_deltas)
          write_operator(:rmoveto)

          advance_state(cmd, master_cmds)
        end

        # ---------- variable lineto ----------

        def encode_variable_lineto(cmd, master_cmds)
          dx, dy, dx_deltas, dy_deltas = compute_variable_deltas(cmd, master_cmds)

          write_variable_number(dx, dx_deltas)
          write_variable_number(dy, dy_deltas)
          write_operator(:rlineto)

          advance_state(cmd, master_cmds)
        end

        # ---------- variable curveto ----------

        def encode_variable_curveto(cmd, master_cmds)
          # Compute relative values for the default master
          dx1 = (cmd[:x1] - @current_x).round
          dy1 = (cmd[:y1] - @current_y).round
          dx2 = (cmd[:x2] - @current_x).round
          dy2 = (cmd[:y2] - @current_y).round
          dx = (cmd[:x] - @current_x).round
          dy = (cmd[:y] - @current_y).round

          base_values = [dx1, dy1, dx2, dy2, dx, dy]
          base_keys = %i[x1 y1 x2 y2 x y]

          # Compute deltas for each coordinate against each master
          all_deltas = base_keys.each_with_index.map do |key, vi|
            master_cmds.each_with_index.map do |mc, i|
              ms = @master_states[i]
              master_relative = if key.to_s.start_with?("x")
                                  (mc[key] - ms.current_x).round
                                else
                                  (mc[key] - ms.current_y).round
                                end
              master_relative - base_values[vi]
            end
          end

          base_values.each_with_index do |val, vi|
            write_variable_number(val, all_deltas[vi])
          end
          write_operator(:rrcurveto)

          advance_state(cmd, master_cmds)
        end

        # ---------- blend emission ----------

        # Emit a variable coordinate: base value + per-region deltas + blend.
        # If all deltas are zero, emits just the base value (no blend needed).
        # @param base_value [Integer] the default-master coordinate
        # @param deltas [Array<Integer>] one delta per variation region
        def write_variable_number(base_value, deltas)
          return write_number(base_value) if deltas.nil? || deltas.empty?
          return write_number(base_value) if deltas.all?(&:zero?)

          @has_blend = true
          write_number(base_value)
          deltas.each { |d| write_number(d) }
          write_number(1) # n = 1 value to blend
          write_operator(:blend)
        end

        def write_vsindex(index)
          write_number(index)
          write_operator(:vsindex)
        end

        def write_operator(operator)
          if OPERATORS_CFF2.key?(operator)
            @output.putc(OPERATORS_CFF2[operator])
          elsif TWO_BYTE_OPERATORS.key?(operator)
            bytes = TWO_BYTE_OPERATORS[operator]
            @output.putc(bytes[0])
            @output.putc(bytes[1])
          else
            raise ArgumentError, "Unknown CFF2 operator: #{operator}"
          end
        end

        private

        # Compute relative deltas for a move/line command and its masters.
        # Returns [dx, dy, dx_deltas, dy_deltas].
        def compute_variable_deltas(cmd, master_cmds)
          dx = (cmd[:x] - @current_x).round
          dy = (cmd[:y] - @current_y).round

          dx_deltas = master_cmds.each_with_index.map do |mc, i|
            master_dx = (mc[:x] - @master_states[i].current_x).round
            master_dx - dx
          end

          dy_deltas = master_cmds.each_with_index.map do |mc, i|
            master_dy = (mc[:y] - @master_states[i].current_y).round
            master_dy - dy
          end

          [dx, dy, dx_deltas, dy_deltas]
        end

        # Update both default and master current positions.
        def advance_state(cmd, master_cmds)
          @current_x = cmd[:x]
          @current_y = cmd[:y]
          master_cmds.each_with_index do |mc, i|
            @master_states[i].current_x = mc[:x]
            @master_states[i].current_y = mc[:y]
          end
        end
      end
    end
  end
end
