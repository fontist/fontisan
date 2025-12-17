# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"
require_relative "../cff/charstring"

module Fontisan
  module Tables
    class Cff2
      # Type 2 CharString parser for CFF2 (variable fonts)
      #
      # CFF2 CharStrings extend Type 2 CharStrings with the blend operator
      # for variation support. The blend operator applies variation deltas
      # to base values based on design space coordinates.
      #
      # Blend Operator (operator 16):
      # - Takes N*K+1 operands where:
      #   - N = number of design variation axes
      #   - K = number of values to blend
      # - Format: [v1, Δv1_axis1, Δv1_axis2, ..., v2, Δv2_axis1, ..., K, N, blend]
      # - Produces K blended values on the stack
      #
      # Example for 2 axes (wght, wdth) blending 3 values:
      #   Input: [100, 10, 5, 200, 20, 10, 50, 5, 2, 3, 2, blend]
      #   - v1=100 with deltas [10, 5]
      #   - v2=200 with deltas [20, 10]
      #   - v3=50 with deltas [5, 2]
      #   - K=3 (number of values), N=2 (number of axes)
      #
      # Reference: Adobe Technical Note #5177 (CFF2 specification)
      #
      # @example Parsing a CFF2 CharString with blend
      #   parser = Fontisan::Tables::Cff2::CharstringParser.new(
      #     data, num_axes, variation_store
      #   )
      #   charstring = parser.parse
      #   puts charstring.path
      #   puts charstring.blend_data
      class CharstringParser
        # @return [String] Binary CharString data
        attr_reader :data

        # @return [Integer] Number of variation axes
        attr_reader :num_axes

        # @return [Array<Hash>] Parsed path commands
        attr_reader :path

        # @return [Array<Hash>] Blend operator data
        attr_reader :blend_data

        # @return [Float] Current X coordinate
        attr_reader :x

        # @return [Float] Current Y coordinate
        attr_reader :y

        # @return [Integer, nil] Glyph width
        attr_reader :width

        # CFF2-specific operators
        BLEND_OPERATOR = 16

        # Initialize parser
        #
        # @param data [String] Binary CharString data
        # @param num_axes [Integer] Number of variation axes (from fvar)
        # @param global_subrs [Cff::Index, nil] Global subroutines INDEX
        # @param local_subrs [Cff::Index, nil] Local subroutines INDEX
        # @param vsindex [Integer] Variation store index (default 0)
        def initialize(data, num_axes = 0, global_subrs = nil, local_subrs = nil, vsindex = 0)
          @data = data
          @num_axes = num_axes
          @global_subrs = global_subrs
          @local_subrs = local_subrs
          @vsindex = vsindex

          @path = []
          @blend_data = []
          @x = 0.0
          @y = 0.0
          @width = nil
          @stems = 0
        end

        # Parse the CharString
        #
        # @return [self]
        def parse
          return self if @parsed

          @stack = []
          @io = StringIO.new(@data)
          @io.set_encoding(Encoding::BINARY)

          parse_charstring_program

          @parsed = true
          self
        end

        # Get blended values for a specific set of coordinates
        #
        # @param coordinates [Hash<String, Float>] Axis coordinates
        # @return [Array<Float>] Blended values
        def blend_values(coordinates)
          return [] if @blend_data.empty?

          # Apply blend operations with coordinates
          @blend_data.map do |blend_op|
            apply_blend(blend_op, coordinates)
          end.flatten
        end

        # Convert path to drawing commands
        #
        # @return [Array<Array>] Array of command arrays
        def to_commands
          @path.map do |cmd|
            case cmd[:type]
            when :move_to
              [:move_to, cmd[:x], cmd[:y]]
            when :line_to
              [:line_to, cmd[:x], cmd[:y]]
            when :curve_to
              [:curve_to, cmd[:x1], cmd[:y1], cmd[:x2], cmd[:y2], cmd[:x], cmd[:y]]
            end
          end
        end

        private

        # Parse the CharString program
        def parse_charstring_program
          until @io.eof?
            byte = @io.getbyte

            if operator_byte?(byte)
              operator = read_operator(byte)
              execute_operator(operator)
            else
              # Operand byte
              @io.pos -= 1
              number = read_number
              @stack << number
            end
          end
        rescue StandardError => e
          raise CorruptedTableError, "Failed to parse CFF2 CharString: #{e.message}"
        end

        # Check if byte is an operator
        #
        # @param byte [Integer] Byte value
        # @return [Boolean] True if operator
        def operator_byte?(byte)
          byte <= 31 && byte != 28
        end

        # Read an operator from the CharString
        #
        # @param first_byte [Integer] First operator byte
        # @return [Integer, Array<Integer>] Operator code
        def read_operator(first_byte)
          if first_byte == 12
            # Two-byte operator
            second_byte = @io.getbyte
            raise CorruptedTableError, "Unexpected end of CharString" if second_byte.nil?

            [12, second_byte]
          else
            # Single-byte operator
            first_byte
          end
        end

        # Read a number from the CharString
        #
        # @return [Integer, Float] The number value
        def read_number
          byte = @io.getbyte
          raise CorruptedTableError, "Unexpected end of CharString" if byte.nil?

          case byte
          when 28
            # 3-byte signed integer (16-bit)
            b1 = @io.getbyte
            b2 = @io.getbyte
            value = (b1 << 8) | b2
            value > 0x7FFF ? value - 0x10000 : value
          when 32..246
            # Small integer: -107 to +107
            byte - 139
          when 247..250
            # Positive 2-byte integer: +108 to +1131
            b2 = @io.getbyte
            (byte - 247) * 256 + b2 + 108
          when 251..254
            # Negative 2-byte integer: -108 to -1131
            b2 = @io.getbyte
            -(byte - 251) * 256 - b2 - 108
          when 255
            # 5-byte signed integer (32-bit) as fixed-point 16.16
            bytes = @io.read(4)
            value = bytes.unpack1("l>") # Signed 32-bit big-endian
            value / 65536.0 # Convert to float
          else
            raise CorruptedTableError, "Invalid CharString number byte: #{byte}"
          end
        end

        # Execute a CharString operator
        #
        # @param operator [Integer, Array<Integer>] Operator code
        def execute_operator(operator)
          case operator
          when BLEND_OPERATOR
            execute_blend
          when 21 # rmoveto
            rmoveto
          when 22 # hmoveto
            hmoveto
          when 4 # vmoveto
            vmoveto
          when 5 # rlineto
            rlineto
          when 6 # hlineto
            hlineto
          when 7 # vlineto
            vlineto
          when 8 # rrcurveto
            rrcurveto
          when 27 # hhcurveto
            hhcurveto
          when 26 # vvcurveto
            vvcurveto
          when 31 # hvcurveto
            hvcurveto
          when 30 # vhcurveto
            vhcurveto
          when 14 # endchar
            endchar
          when 1, 3, 18, 23 # hstem, vstem, hstemhm, vstemhm
            hint_operator
          when 19, 20 # hintmask, cntrmask
            hintmask_operator
          when 10 # callsubr
            callsubr
          when 29 # callgsubr
            callgsubr
          else
            # Unknown operator - clear stack
            @stack.clear
          end
        end

        # Execute blend operator
        #
        # Stack: v1 Δv1_1 ... Δv1_N v2 Δv2_1 ... Δv2_N ... K N blend
        # Result: blended_v1 blended_v2 ... blended_vK
        def execute_blend
          return if @stack.size < 2

          # Pop N (number of axes) and K (number of values to blend)
          n = @stack.pop.to_i
          k = @stack.pop.to_i

          # Validate we have enough operands: K * (N + 1)
          required_operands = k * (n + 1)
          if @stack.size < required_operands
            warn "Blend operator requires #{required_operands} operands, got #{@stack.size}"
            @stack.clear
            return
          end

          # Extract base values and deltas
          blend_operands = @stack.pop(required_operands)
          blends = []

          k.times do |i|
            offset = i * (n + 1)
            base_value = blend_operands[offset]
            deltas = blend_operands[offset + 1, n] || []

            blends << {
              base: base_value,
              deltas: deltas,
              num_axes: n,
            }

            # For now, push base value back (will be blended later with coordinates)
            @stack << base_value
          end

          # Store blend data for later application
          @blend_data << {
            num_values: k,
            num_axes: n,
            blends: blends,
          }
        end

        # Apply blend operation with coordinates
        #
        # @param blend_op [Hash] Blend operation data
        # @param coordinates [Hash<String, Float>] Axis coordinates
        # @return [Array<Float>] Blended values
        def apply_blend(blend_op, coordinates)
          blend_op[:blends].map do |blend|
            base = blend[:base]
            deltas = blend[:deltas]

            # Apply deltas based on coordinates
            # This will be enhanced when we have proper coordinate interpolation
            blended_value = base
            deltas.each_with_index do |delta, axis_index|
              # Placeholder: use normalized coordinate (will be replaced with proper interpolation)
              scalar = 0.0 # Will be calculated by interpolator
              blended_value += delta * scalar
            end

            blended_value
          end
        end

        # Path construction operators (simplified implementations)

        def rmoveto
          return if @stack.size < 2

          dy = @stack.pop
          dx = @stack.pop
          @x += dx
          @y += dy
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

        def hmoveto
          return if @stack.empty?

          dx = @stack.pop
          @x += dx
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

        def vmoveto
          return if @stack.empty?

          dy = @stack.pop
          @y += dy
          @path << { type: :move_to, x: @x, y: @y }
          @stack.clear
        end

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

        def hhcurveto
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

        def vvcurveto
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

        def hvcurveto
          horizontal_first = true
          while @stack.size >= 4
            if horizontal_first
              dx1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dy3 = @stack.shift
              dx3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x + dx1
              y1 = @y
            else
              dy1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dx3 = @stack.shift
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

        def vhcurveto
          vertical_first = true
          while @stack.size >= 4
            if vertical_first
              dy1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dx3 = @stack.shift
              dy3 = @stack.size == 1 ? @stack.shift : 0

              x1 = @x
              y1 = @y + dy1
            else
              dx1 = @stack.shift
              dx2 = @stack.shift
              dy2 = @stack.shift
              dy3 = @stack.shift
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

        def endchar
          @stack.clear
        end

        def hint_operator
          @stems += @stack.size / 2
          @stack.clear
        end

        def hintmask_operator
          hint_bytes = (@stems + 7) / 8
          @io.read(hint_bytes)
          @stack.clear
        end

        def callsubr
          return if @local_subrs.nil? || @stack.empty?

          subr_index = @stack.pop
          # Implement subroutine call (placeholder)
          @stack.clear
        end

        def callgsubr
          return if @global_subrs.nil? || @stack.empty?

          subr_index = @stack.pop
          # Implement global subroutine call (placeholder)
          @stack.clear
        end
      end
    end
  end
end
