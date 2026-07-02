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
      # The blend protocol:
      #   1. Push n base values for the coordinates to vary
      #   2. Push n * num_regions delta values (axis-ordered)
      #   3. Emit blend → pops n*(num_regions+1), pushes n blended values
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2#charstring-operators
      class Cff2CharStringBuilder < CharStringBuilder
        # CFF2 replaces hmoveto(22) with vsindex(22). The :hmoveto key
        # is omitted entirely so attempts to emit it raise naturally.
        OPERATORS_CFF2 = OPERATORS.except(:hmoveto).merge(
          vsindex: 22,
          blend: 23,
        )

        def write_vsindex(index)
          write_number(index)
          write_operator(:vsindex)
        end

        # Emit deltas followed by the blend operator. The caller is
        # responsible for pushing the n base values first.
        # @param deltas [Array<Integer>] per-region delta values
        def write_blend(deltas)
          deltas.each { |d| write_number(d) }
          write_operator(:blend)
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
      end
    end
  end
end
