# frozen_string_literal: true

require "stringio"

module Fontisan
  module Optimizers
    # Tracks operand stack depth during CharString execution without full
    # interpretation. Used to identify stack-neutral patterns suitable for
    # subroutinization.
    #
    # A stack-neutral pattern is one where the stack depth is the same before
    # and after the pattern executes. This ensures that replacing the pattern
    # with a subroutine call won't cause stack underflow/overflow.
    #
    # @example Basic usage
    #   tracker = StackTracker.new(charstring_bytes)
    #   stack_map = tracker.track
    #   start_depth = stack_map[start_pos]
    #   end_depth = stack_map[end_pos]
    #   is_neutral = (start_depth == end_depth)
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class StackTracker
      # Type 2 CharString operator stack effects
      # Maps operator => [operands_consumed, operands_produced]
      OPERATOR_STACK_EFFECTS = {
        # Path construction operators
        hstem: [2, 0],           # y dy hstem
        vstem: [2, 0],           # x dx vstem
        vmoveto: [1, 0],         # dy vmoveto
        rlineto: [-1, 0],        # {dxa dya}+ (variable, pairs)
        hlineto: [-1, 0],        # dx1 {dya dxb}* (variable, alternating)
        vlineto: [-1, 0],        # dy1 {dxb dya}* (variable, alternating)
        rrcurveto: [-1, 0],      # {dxa dya dxb dyb dxc dyc}+ (variable, 6-tuples)
        callsubr: [1, 0],        # subr# callsubr (note: subr may affect stack)
        return: [0, 0],          # return
        endchar: [0, 0],         # endchar
        hstemhm: [2, 0],         # y dy hstemhm
        hintmask: [0, 0],        # hintmask
        cntrmask: [0, 0],        # cntrmask
        rmoveto: [2, 0],         # dx dy rmoveto
        hmoveto: [1, 0],         # dx hmoveto
        vstemhm: [2, 0],         # x dx vstemhm
        rcurveline: [-1, 0],     # {dxa dya dxb dyb dxc dyc}+ dxd dyd (variable)
        rlinecurve: [-1, 0],     # {dxa dya}+ dxb dyb dxc dyc dxd dyd (variable)
        vvcurveto: [-1, 0],      # dx1? {dya dxb dyb dyc}+ (variable)
        hhcurveto: [-1, 0],      # dy1? {dxa dxb dyb dxc}+ (variable)
        shortint: [0, 1],        # (16-bit number)
        callgsubr: [1, 0],       # subr# callgsubr
        vhcurveto: [-1, 0],      # dy1 dx2 dy2 dx3 {dxa dxb dyb dyc dyd dxe dye dxf}* (variable)
        hvcurveto: [-1, 0],      # dx1 dx2 dy2 dy3 {dya dxb dyb dxc dxd dxe dye dyf}* (variable)

        # Arithmetic operators (12 prefix)
        and: [2, 1],             # num1 num2 and
        or: [2, 1],              # num1 num2 or
        not: [1, 1],             # num1 not
        abs: [1, 1],             # num abs
        add: [2, 1],             # num1 num2 add
        sub: [2, 1],             # num1 num2 sub
        div: [2, 1],             # num1 num2 div
        neg: [1, 1],             # num neg
        eq: [2, 1],              # num1 num2 eq
        drop: [1, 0],            # any drop
        put: [2, 0],             # val i put
        get: [1, 1],             # i get
        ifelse: [4, 1],          # v1 v2 s1 s2 ifelse
        random: [0, 1],          # random
        mul: [2, 1],             # num1 num2 mul
        sqrt: [1, 1],            # num sqrt
        dup: [1, 2],             # any dup
        exch: [2, 2],            # any1 any2 exch
        index: [1, 1],           # i index (actually [i+1, i+1])
        roll: [2, 0],            # N J roll (rotates top N elements)

        # Flex operators (12 prefix)
        hflex: [7, 0],           # dx1 dx2 dy2 dx3 dx4 dx5 dx6 hflex
        flex: [13, 0],           # dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 dx6 dy6 fd flex
        hflex1: [9, 0],          # dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6 hflex1
        flex1: [11, 0],          # dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 d6 flex1
      }.freeze

      # Type 2 CharString operator codes
      OPERATORS = {
        1 => :hstem,
        3 => :vstem,
        4 => :vmoveto,
        5 => :rlineto,
        6 => :hlineto,
        7 => :vlineto,
        8 => :rrcurveto,
        10 => :callsubr,
        11 => :return,
        14 => :endchar,
        18 => :hstemhm,
        19 => :hintmask,
        20 => :cntrmask,
        21 => :rmoveto,
        22 => :hmoveto,
        23 => :vstemhm,
        24 => :rcurveline,
        25 => :rlinecurve,
        26 => :vvcurveto,
        27 => :hhcurveto,
        28 => :shortint,
        29 => :callgsubr,
        30 => :vhcurveto,
        31 => :hvcurveto,
        [12, 3] => :and,
        [12, 4] => :or,
        [12, 5] => :not,
        [12, 9] => :abs,
        [12, 10] => :add,
        [12, 11] => :sub,
        [12, 12] => :div,
        [12, 14] => :neg,
        [12, 15] => :eq,
        [12, 18] => :drop,
        [12, 20] => :put,
        [12, 21] => :get,
        [12, 22] => :ifelse,
        [12, 23] => :random,
        [12, 24] => :mul,
        [12, 26] => :sqrt,
        [12, 27] => :dup,
        [12, 28] => :exch,
        [12, 29] => :index,
        [12, 30] => :roll,
        [12, 34] => :hflex,
        [12, 35] => :flex,
        [12, 36] => :hflex1,
        [12, 37] => :flex1,
      }.freeze

      # Initialize stack tracker
      # @param charstring [String] CharString bytes to track
      def initialize(charstring)
        @charstring = charstring
        @stack_depth_map = {}
      end

      # Track stack depth at each byte position
      # @return [Hash<Integer, Integer>] position => stack_depth
      def track
        io = StringIO.new(@charstring)
        depth = 0

        # Record initial depth
        @stack_depth_map[0] = depth

        while !io.eof?
          byte = io.getbyte

          if byte <= 31 && byte != 28
            # Operator
            operator = read_operator(io, byte)
            depth = apply_operator_effect(operator, depth)
          else
            # Number - pushes one value
            io.pos -= 1
            skip_number(io)
            depth += 1
          end

          # Record depth after processing this element
          @stack_depth_map[io.pos] = depth
        end

        @stack_depth_map
      end

      # Check if a pattern is stack-neutral
      # @param start_pos [Integer] pattern start position
      # @param end_pos [Integer] pattern end position (exclusive)
      # @return [Boolean] true if stack depth is same at start and end
      def stack_neutral?(start_pos, end_pos)
        return false unless @stack_depth_map.key?(start_pos)
        return false unless @stack_depth_map.key?(end_pos)

        @stack_depth_map[start_pos] == @stack_depth_map[end_pos]
      end

      # Get stack depth at a position
      # @param position [Integer] byte position
      # @return [Integer, nil] stack depth or nil if not tracked
      def depth_at(position)
        @stack_depth_map[position]
      end

      private

      # Read operator from CharString
      def read_operator(io, first_byte)
        if first_byte == 12
          second_byte = io.getbyte
          return :unknown if second_byte.nil?

          operator_key = [first_byte, second_byte]
          OPERATORS[operator_key] || :unknown
        else
          OPERATORS[first_byte] || :unknown
        end
      end

      # Skip over a number without reading its value
      def skip_number(io)
        byte = io.getbyte
        return if byte.nil?

        case byte
        when 28
          # 3-byte signed integer
          io.read(2)
        when 32..246
          # Single byte integer
        when 247..254
          # 2-byte integer
          io.getbyte
        when 255
          # 5-byte integer
          io.read(4)
        end
      end

      # Apply operator's stack effect
      def apply_operator_effect(operator, current_depth)
        effect = OPERATOR_STACK_EFFECTS[operator]
        return current_depth if effect.nil? # Unknown operator

        consumed, produced = effect

        if consumed == -1
          # Variable consumption - need special handling
          # For now, conservatively assume it consumes all available operands
          new_depth = produced
        else
          new_depth = current_depth - consumed + produced
          # Ensure depth doesn't go negative
          new_depth = 0 if new_depth.negative?
        end

        new_depth
      end
    end
  end
end
