# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # Type 2 CharString interpreter
      #
      # CharStrings are stack-based programs that draw glyph outlines using
      # a series of operators. They are stored in the CharStrings INDEX and
      # contain path construction, hinting, and arithmetic operations.
      #
      # Type 2 CharString Format:
      # - Numbers are pushed onto an operand stack
      # - Operators pop operands and execute commands
      # - Path operators build the glyph outline
      # - Hint operators define stem hints (can be ignored for rendering)
      # - Subroutine operators allow code reuse
      # - Arithmetic operators perform calculations on the stack
      #
      # Path Construction Flow:
      # 1. Optional width value (first operand if odd number before first move)
      # 2. Initial moveto operator to start a path
      # 3. Line/curve operators to construct the path
      # 4. Optional closepath (implicit at endchar)
      # 5. endchar to finish the glyph
      #
      # Reference: Adobe Type 2 CharString Format
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf
      #
      # @example Interpreting a CharString
      #   charstring = CharString.new(data, private_dict, global_subrs,
      #                               local_subrs)
      #   puts charstring.width  # => glyph width
      #   puts charstring.path   # => array of path commands
      #   bbox = charstring.bounding_box  # => [xMin, yMin, xMax, yMax]
      class CharString
        # @return [Integer, nil] Glyph width (nil if using default width)
        attr_reader :width

        # @return [Array<Hash>] Path commands array
        attr_reader :path

        # @return [Float] Current X coordinate
        attr_reader :x

        # @return [Float] Current Y coordinate
        attr_reader :y

        # Type 2 CharString operators
        #
        # These operators define the behavior of the CharString interpreter
        OPERATORS = {
          # Path construction operators
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
          # 12 prefix for two-byte operators
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

        # Initialize and interpret a CharString
        #
        # @param data [String] Binary CharString data
        # @param private_dict [PrivateDict] Private DICT for width defaults
        # @param global_subrs [Index] Global subroutines INDEX
        # @param local_subrs [Index, nil] Local subroutines INDEX
        def initialize(data, private_dict, global_subrs, local_subrs = nil)
          @data = data
          @private_dict = private_dict
          @global_subrs = global_subrs
          @local_subrs = local_subrs

          @stack = []
          @path = []
          @x = 0.0
          @y = 0.0
          @width = nil
          @stems = 0
          @transient_array = []
          @subroutine_bias = calculate_bias(local_subrs)
          @global_subroutine_bias = calculate_bias(global_subrs)

          parse!
        end

        # Calculate the bounding box of the glyph
        #
        # @return [Array<Float>] [xMin, yMin, xMax, yMax] or nil if no path
        def bounding_box
          return nil if @path.empty?

          x_coords = []
          y_coords = []

          @path.each do |cmd|
            case cmd[:type]
            when :move_to, :line_to
              x_coords << cmd[:x]
              y_coords << cmd[:y]
            when :curve_to
              x_coords << cmd[:x1] << cmd[:x2] << cmd[:x]
              y_coords << cmd[:y1] << cmd[:y2] << cmd[:y]
            end
          end

          return nil if x_coords.empty?

          [x_coords.min, y_coords.min, x_coords.max, y_coords.max]
        end

        # Convert path to drawing commands
        #
        # @return [Array<Array>] Array of command arrays:
        #   [:move_to, x, y], [:line_to, x, y], [:curve_to, x1, y1, x2, y2,
        #   x, y]
        def to_commands
          @path.map do |cmd|
            case cmd[:type]
            when :move_to
              [:move_to, cmd[:x], cmd[:y]]
            when :line_to
              [:line_to, cmd[:x], cmd[:y]]
            when :curve_to
              [:curve_to, cmd[:x1], cmd[:y1], cmd[:x2], cmd[:y2],
               cmd[:x], cmd[:y]]
            end
          end
        end

        private

        # Parse and execute the CharString program
        def parse!
          io = StringIO.new(@data)
          width_parsed = false

          until io.eof?
            byte = io.getbyte

            if byte <= 31 && byte != 28
              # Operator byte
              operator = read_operator(io, byte)
              result = execute_operator(operator, width_parsed)
              # Mark width as parsed after move operators or hint operators
              if result == true || %i[hstem vstem hstemhm
                                      vstemhm].include?(operator)
                width_parsed = true
              end
            else
              # Operand byte
              io.pos -= 1
              number = read_number(io)
              @stack << number
            end
          end
        rescue StandardError => e
          raise CorruptedTableError,
                "Failed to parse CharString: #{e.message}"
        end

        # Read an operator from the CharString
        #
        # @param io [StringIO] Input stream
        # @param first_byte [Integer] First operator byte
        # @return [Symbol] Operator name
        def read_operator(io, first_byte)
          if first_byte == 12
            # Two-byte operator
            second_byte = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString" if
              second_byte.nil?

            operator_key = [first_byte, second_byte]
            OPERATORS[operator_key] || :unknown
          else
            # Single-byte operator
            OPERATORS[first_byte] || :unknown
          end
        end

        # Read a number (integer or real) from the CharString
        #
        # @param io [StringIO] Input stream
        # @return [Integer, Float] The number value
        def read_number(io)
          byte = io.getbyte
          raise CorruptedTableError, "Unexpected end of CharString" if
            byte.nil?

          case byte
          when 28
            # 3-byte signed integer (16-bit)
            b1 = io.getbyte
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading shortint" if
              b1.nil? || b2.nil?
            value = (b1 << 8) | b2
            value > 0x7FFF ? value - 0x10000 : value
          when 32..246
            # Small integer: -107 to +107
            byte - 139
          when 247..250
            # Positive 2-byte integer: +108 to +1131
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading positive integer" if
              b2.nil?
            (byte - 247) * 256 + b2 + 108
          when 251..254
            # Negative 2-byte integer: -108 to -1131
            b2 = io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString reading negative integer" if
              b2.nil?
            -(byte - 251) * 256 - b2 - 108
          when 255
            # 5-byte signed integer (32-bit) as fixed-point 16.16
            bytes = io.read(4)
            raise CorruptedTableError, "Unexpected end of CharString reading fixed-point" if
              bytes.nil? || bytes.length < 4
            value = bytes.unpack1("l>") # Signed 32-bit big-endian
            value / 65536.0 # Convert to float
          else
            raise CorruptedTableError, "Invalid CharString number byte: #{byte}"
          end
        end

        # Execute a CharString operator
        #
        # @param operator [Symbol] Operator name
        # @param width_parsed [Boolean] Whether width has been parsed
        def execute_operator(operator, width_parsed)
          case operator
          # Path construction operators
          when :rmoveto
            rmoveto(width_parsed)
            true # Width has now been parsed
          when :hmoveto
            hmoveto(width_parsed)
            true # Width has now been parsed
          when :vmoveto
            vmoveto(width_parsed)
            true # Width has now been parsed
          when :rlineto
            rlineto
          when :hlineto
            hlineto
          when :vlineto
            vlineto
          when :rrcurveto
            rrcurveto
          when :hhcurveto
            hhcurveto
          when :vvcurveto
            vvcurveto
          when :hvcurveto
            hvcurveto
          when :vhcurveto
            vhcurveto
          when :rcurveline
            rcurveline
          when :rlinecurve
            rlinecurve
          when :endchar
            endchar

          # Hint operators (stub for now)
          when :hstem, :vstem, :hstemhm, :vstemhm
            hint_operator(width_parsed)
          when :hintmask, :cntrmask
            hintmask_operator

          # Subroutine operators
          when :callsubr
            callsubr
          when :callgsubr
            callgsubr
          when :return
          # Return is handled by subroutine execution

          # Arithmetic operators
          when :add
            arithmetic_add
          when :sub
            arithmetic_sub
          when :mul
            arithmetic_mul
          when :div
            arithmetic_div
          when :neg
            arithmetic_neg
          when :abs
            arithmetic_abs
          when :sqrt
            arithmetic_sqrt
          when :drop
            @stack.pop
          when :exch
            @stack[-1], @stack[-2] = @stack[-2], @stack[-1]
          when :dup
            @stack << @stack.last
          when :put
            value = @stack.pop
            index = @stack.pop
            @transient_array[index] = value
          when :get
            index = @stack.pop
            @stack << (@transient_array[index] || 0)

          # Flex operators
          when :hflex, :flex, :hflex1, :flex1
            flex_operator(operator)

          when :unknown
            # Unknown operator - clear stack and continue
            @stack.clear
          end
        end

        # rmoveto: dx dy rmoveto
        # Relative move to (dx, dy)
        def rmoveto(width_parsed)
          # rmoveto takes 2 operands, so if stack has 3 and width not parsed,
          # first is width
          parse_width_for_operator(width_parsed, 2)
          return if @stack.size < 2  # Need at least 2 values
          dy = @stack.pop
          dx = @stack.pop
          @x += dx
          @y += dy
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

        # hmoveto: dx hmoveto
        # Horizontal move to (dx, 0)
        def hmoveto(width_parsed)
          # hmoveto takes 1 operand, so if stack has 2 and width not parsed,
          # first is width
          parse_width_for_operator(width_parsed, 1)
          return if @stack.empty?  # Need at least 1 value
          dx = @stack.pop || 0
          @x += dx
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

        # vmoveto: dy vmoveto
        # Vertical move to (0, dy)
        def vmoveto(width_parsed)
          # vmoveto takes 1 operand, so if stack has 2 and width not parsed,
          # first is width
          parse_width_for_operator(width_parsed, 1)
          return if @stack.empty?  # Need at least 1 value
          dy = @stack.pop || 0
          @y += dy
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

        # rlineto: {dxa dya}+ rlineto
        # Relative line to
        def rlineto
          while @stack.size >= 2
            dx = @stack.shift
            dy = @stack.shift
            @x += dx
            @y += dy
            @path << { type: :line_to, x: @x, y: @y }
          end
          @stack.clear
        end

        # hlineto: dx1 {dya dxb}* hlineto
        # Alternating horizontal and vertical lines
        def hlineto
          horizontal = true
          while @stack.any?
            delta = @stack.shift
            if horizontal
              @x += delta
            else
              @y += delta
            end
            @path << { type: :line_to, x: @x, y: @y }
            horizontal = !horizontal
          end
          @stack.clear
        end

        # vlineto: dy1 {dxb dya}* vlineto
        # Alternating vertical and horizontal lines
        def vlineto
          vertical = true
          while @stack.any?
            delta = @stack.shift
            if vertical
              @y += delta
            else
              @x += delta
            end
            @path << { type: :line_to, x: @x, y: @y }
            vertical = !vertical
          end
          @stack.clear
        end

        # rrcurveto: {dxa dya dxb dyb dxc dyc}+ rrcurveto
        # Relative cubic Bézier curve
        def rrcurveto
          while @stack.size >= 6
            dx1 = @stack.shift
            dy1 = @stack.shift
            dx2 = @stack.shift
            dy2 = @stack.shift
            dx3 = @stack.shift
            dy3 = @stack.shift

            x1 = @x + dx1
            y1 = @y + dy1
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
          end
          @stack.clear
        end

        # hhcurveto: dy1? {dxa dxb dyb dxc}+ hhcurveto
        # Horizontal-horizontal curve
        def hhcurveto
          # First value might be dy1 if odd number of args
          if @stack.size.odd?
            @y += @stack.shift
          end

          while @stack.size >= 4
            dx1 = @stack.shift
            dx2 = @stack.shift
            dy2 = @stack.shift
            dx3 = @stack.shift

            x1 = @x + dx1
            y1 = @y
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
          end
          @stack.clear
        end

        # vvcurveto: dx1? {dya dxb dyb dyc}+ vvcurveto
        # Vertical-vertical curve
        def vvcurveto
          # First value might be dx1 if odd number of args
          if @stack.size.odd?
            @x += @stack.shift
          end

          while @stack.size >= 4
            dy1 = @stack.shift
            dx2 = @stack.shift
            dy2 = @stack.shift
            dy3 = @stack.shift

            x1 = @x
            y1 = @y + dy1
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
          end
          @stack.clear
        end

        # hvcurveto: dx1 dx2 dy2 dy3 {dya dxb dyb dxc dxd dxe dye dyf}* dxf?
        # hvcurveto
        # Horizontal-vertical curve
        def hvcurveto
          horizontal_first = true
          while @stack.size >= 4
            if horizontal_first
              dx1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dy3 = @stack.shift
              # Handle final dx if this is the last curve
              dx3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x + dx1
              y1 = @y
            else
              dy1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dx3 = @stack.shift
              # Handle final dy if this is the last curve
              dy3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x
              y1 = @y + dy1
            end
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
            horizontal_first = !horizontal_first
          end
          @stack.clear
        end

        # vhcurveto: dy1 dx2 dy2 dx3 {dxa dxb dyb dyc dyd dxe dye dxf}* dyf?
        # vhcurveto
        # Vertical-horizontal curve
        def vhcurveto
          vertical_first = true
          while @stack.size >= 4
            if vertical_first
              dy1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dx3 = @stack.shift
              # Handle final dy if this is the last curve
              dy3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x
              y1 = @y + dy1
            else
              dx1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dy3 = @stack.shift
              # Handle final dx if this is the last curve
              dx3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x + dx1
              y1 = @y
            end
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
            vertical_first = !vertical_first
          end
          @stack.clear
        end

        # rcurveline: {dxa dya dxb dyb dxc dyc}+ dxd dyd rcurveline
        # Curves followed by a line
        def rcurveline
          # Process curves (all but last 2 values)
          while @stack.size > 2
            break if @stack.size < 6

            dx1 = @stack.shift
            dy1 = @stack.shift
            dx2 = @stack.shift
            dy2 = @stack.shift
            dx3 = @stack.shift
            dy3 = @stack.shift

            x1 = @x + dx1
            y1 = @y + dy1
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
          end

          # Process final line
          if @stack.size == 2
            dx = @stack.shift
            dy = @stack.shift
            @x += dx
            @y += dy
            @path << { type: :line_to, x: @x, y: @y }
          end
          @stack.clear
        end

        # rlinecurve: {dxa dya}+ dxb dyb dxc dyc dxd dyd rlinecurve
        # Lines followed by a curve
        def rlinecurve
          # Process lines (all but last 6 values)
          while @stack.size > 6
            dx = @stack.shift
            dy = @stack.shift
            @x += dx
            @y += dy
            @path << { type: :line_to, x: @x, y: @y }
          end

          # Process final curve
          if @stack.size == 6
            dx1 = @stack.shift
            dy1 = @stack.shift
            dx2 = @stack.shift
            dy2 = @stack.shift
            dx3 = @stack.shift
            dy3 = @stack.shift

            x1 = @x + dx1
            y1 = @y +dy1
            x2 = x1 + dx2
            y2 = y1 + dy2
            @x = x2 + dx3
            @y = y2 + dy3

            @path << {
              type: :curve_to,
              x1: x1, y1: y1,
              x2: x2, y2: y2,
              x: @x, y: @y
            }
          end
          @stack.clear
        end

        # endchar: endchar
        # End of glyph definition
        def endchar
          # Implicitly closes the path
          @stack.clear
        end

        # Hint operators (stubbed - hints not needed for rendering)
        def hint_operator(width_parsed)
          parse_width_if_needed(width_parsed) unless width_parsed
          # Count stems for width calculation
          @stems += @stack.size / 2
          @stack.clear
        end

        # Hintmask/cntrmask operators
        def hintmask_operator
          # Calculate number of bytes needed for hint mask
          hint_bytes = (@stems + 7) / 8
          # Skip hint mask bytes (not needed for rendering)
          @io&.read(hint_bytes)
          @stack.clear
        end

        # Flex operators (convert to curves)
        def flex_operator(operator)
          case operator
          when :hflex
            # dx1 dx2 dy2 dx3 dx4 dx5 dx6 hflex
            dx1, dx2, dy2, dx3, dx4, dx5, dx6 = @stack.shift(7)
            # Convert to two curves
            add_curve(dx1, 0, dx2, dy2, dx3, 0)
            add_curve(dx4, 0, dx5, -dy2, dx6, 0)
          when :flex
            # dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 dx6 dy6 fd flex
            dx1, dy1, dx2, dy2, dx3, dy3, dx4, dy4, dx5, dy5, dx6, dy6,
              _fd = @stack.shift(13)
            # Convert to two curves
            add_curve(dx1, dy1, dx2, dy2, dx3, dy3)
            add_curve(dx4, dy4, dx5, dy5, dx6, dy6)
          when :hflex1
            # dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6 hflex1
            dx1, dy1, dx2, dy2, dx3, dx4, dx5, dy5, dx6 = @stack.shift(9)
            add_curve(dx1, dy1, dx2, dy2, dx3, 0)
            add_curve(dx4, 0, dx5, dy5, dx6, -(dy1 + dy2 + dy5))
          when :flex1
            # dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 d6 flex1
            dx1, dy1, dx2, dy2, dx3, dy3, dx4, dy4, dx5, dy5, d6 =
              @stack.shift(11)
            dx = dx1 + dx2 + dx3 + dx4 + dx5
            dy = dy1 + dy2 + dy3 + dy4 + dy5
            add_curve(dx1, dy1, dx2, dy2, dx3, dy3)
            if dx.abs > dy.abs
              add_curve(dx4, dy4, dx5, dy5, d6, -dy)
            else
              add_curve(dx4, dy4, dx5, dy5, -dx, d6)
            end
          end
          @stack.clear
        end

        # Helper to add a curve to the path
        def add_curve(dx1, dy1, dx2, dy2, dx3, dy3)
          x1 = @x + dx1
          y1 = @y + dy1
          x2 = x1 + dx2
          y2 = y1 + dy2
          @x = x2 + dx3
          @y = y2 + dy3

          @path << {
            type: :curve_to,
            x1: x1, y1: y1,
            x2: x2, y2: y2,
            x: @x, y: @y
          }
        end

        # Call local subroutine
        def callsubr
          return if @stack.empty?
          subr_num = @stack.pop
          return unless subr_num # Guard against empty stack

          subr_index = subr_num + @subroutine_bias
          if @local_subrs && subr_index >= 0 && subr_index < @local_subrs.count
            subr_data = @local_subrs[subr_index]
            execute_subroutine(subr_data)
          end
        end

        # Call global subroutine
        def callgsubr
          return if @stack.empty?
          subr_num = @stack.pop
          return unless subr_num # Guard against empty stack

          subr_index = subr_num + @global_subroutine_bias
          if subr_index >= 0 && subr_index < @global_subrs.count
            subr_data = @global_subrs[subr_index]
            execute_subroutine(subr_data)
          end
        end

        # Execute a subroutine
        def execute_subroutine(data)
          saved_io = @io
          saved_data = @data
          @data = data
          @io = StringIO.new(data)

          # Process subroutine until return or end
          until @io.eof?
            byte = @io.getbyte

            if byte <= 31 && byte != 28
              operator = read_operator(@io, byte)
              break if operator == :return

              execute_operator(operator, true) # Width already parsed
            else
              @io.pos -= 1
              number = read_number(@io)
              @stack << number
            end
          end

          @io = saved_io
          @data = saved_data
        end

        # Arithmetic operators
        def arithmetic_add
          return if @stack.size < 2
          b = @stack.pop
          a = @stack.pop
          @stack << (a + b)
        end

        def arithmetic_sub
          return if @stack.size < 2
          b = @stack.pop
          a = @stack.pop
          @stack << (a - b)
        end

        def arithmetic_mul
          return if @stack.size < 2
          b = @stack.pop
          a = @stack.pop
          @stack << (a * b)
        end

        def arithmetic_div
          return if @stack.size < 2
          b = @stack.pop
          a = @stack.pop
          return if b.zero?
          @stack << (a / b.to_f)
        end

        def arithmetic_neg
          return if @stack.empty?
          @stack << -@stack.pop
        end

        def arithmetic_abs
          return if @stack.empty?
          @stack << @stack.pop.abs
        end

        def arithmetic_sqrt
          return if @stack.empty?
          val = @stack.pop
          return if val.negative?
          @stack << Math.sqrt(val)
        end

        # Parse width for a specific operator
        #
        # @param width_parsed [Boolean] Whether width has already been parsed
        # @param expected_operands [Integer] Number of operands this operator
        #   expects
        def parse_width_for_operator(width_parsed, expected_operands)
          return if width_parsed || @width

          # Width is present if there's one more operand than expected
          if @stack.size == expected_operands + 1
            width_value = @stack.shift
            @width = @private_dict.nominal_width_x + width_value
          else
            @width = @private_dict.default_width_x
          end
        end

        # Parse width if present (for hint operators)
        def parse_width_if_needed(width_parsed)
          return if width_parsed || @width

          # For hint operators, width is present if odd number of operands
          if @stack.size.odd?
            width_value = @stack.shift
            @width = @private_dict.nominal_width_x + width_value
          else
            @width = @private_dict.default_width_x
          end
        end

        # Calculate subroutine bias based on INDEX count
        #
        # @param index [Index, nil] Subroutine INDEX
        # @return [Integer] Bias value
        def calculate_bias(index)
          return 0 unless index

          count = index.count
          if count < 1240
            107
          elsif count < 33900
            1131
          else
            32768
          end
        end
      end
    end
  end
end
