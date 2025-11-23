# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff
      # Type 2 CharString builder/encoder
      #
      # [`CharStringBuilder`](lib/fontisan/tables/cff/charstring_builder.rb)
      # encodes glyph outlines into Type 2 CharString binary format. It takes
      # high-level outline commands and produces the stack-based CharString
      # operators used in CFF fonts.
      #
      # Type 2 CharString encoding:
      # - Numbers are encoded in various compact formats
      # - Operators are single or two-byte commands
      # - All coordinates are relative (dx, dy format)
      # - Current point tracking for relative calculations
      #
      # Operator optimization:
      # - Use specialized operators (hlineto, vlineto) when possible
      # - Merge sequential operators of same type
      # - Minimize operator bytes
      #
      # Reference: Adobe Type 2 CharString Format
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf
      #
      # @example Building a CharString from outline
      #   builder = Fontisan::Tables::Cff::CharStringBuilder.new
      #   charstring_data = builder.build(outline, width: 500)
      class CharStringBuilder
        # Type 2 CharString operators (opposite of parser)
        OPERATORS = {
          hstem: 1,
          vstem: 3,
          vmoveto: 4,
          rlineto: 5,
          hlineto: 6,
          vlineto: 7,
          rrcurveto: 8,
          callsubr: 10,
          return: 11,
          endchar: 14,
          hstemhm: 18,
          hintmask: 19,
          cntrmask: 20,
          rmoveto: 21,
          hmoveto: 22,
          vstemhm: 23,
          rcurveline: 24,
          rlinecurve: 25,
          vvcurveto: 26,
          hhcurveto: 27,
          shortint: 28,
          callgsubr: 29,
          vhcurveto: 30,
          hvcurveto: 31,
        }.freeze

        # Two-byte operators (12 prefix)
        TWO_BYTE_OPERATORS = {
          and: [12, 3],
          or: [12, 4],
          not: [12, 5],
          abs: [12, 9],
          add: [12, 10],
          sub: [12, 11],
          div: [12, 12],
          neg: [12, 14],
          eq: [12, 15],
          drop: [12, 18],
          put: [12, 20],
          get: [12, 21],
          ifelse: [12, 22],
          random: [12, 23],
          mul: [12, 24],
          sqrt: [12, 26],
          dup: [12, 27],
          exch: [12, 28],
          index: [12, 29],
          roll: [12, 30],
          hflex: [12, 34],
          flex: [12, 35],
          hflex1: [12, 36],
          flex1: [12, 37],
        }.freeze

        # Build a CharString from an outline
        #
        # @param outline [Models::Outline] Universal outline object
        # @param width [Integer, nil] Glyph width (optional)
        # @return [String] Binary CharString data
        def build(outline, width: nil)
          @output = StringIO.new("".b)
          @current_x = 0.0
          @current_y = 0.0
          @first_move = true

          # Convert outline to CFF commands
          commands = outline.to_cff_commands

          # Encode width if provided (before first move)
          if width && !commands.empty?
            # Width is encoded as first operator before first move
            # For now, we'll add it before the first moveto
            encode_width(width)
          end

          # Encode each command
          commands.each do |cmd|
            encode_command(cmd)
          end

          # End character
          write_operator(:endchar)

          @output.string
        end

        # Build an empty CharString (for .notdef or empty glyphs)
        #
        # @param width [Integer, nil] Glyph width
        # @return [String] Binary CharString data
        def build_empty(width: nil)
          @output = StringIO.new("".b)

          # Encode width if provided
          encode_width(width) if width

          # Just endchar for empty glyph
          write_operator(:endchar)

          @output.string
        end

        private

        # Encode a width value
        #
        # Width is encoded as a delta from nominal width
        # For simplicity, we encode as-is (assuming nominal width is 0)
        #
        # @param width [Integer] Width value
        def encode_width(width)
          write_number(width)
        end

        # Encode a single command
        #
        # @param cmd [Hash] Command hash with :type and coordinates
        def encode_command(cmd)
          case cmd[:type]
          when :move_to
            encode_moveto(cmd)
          when :line_to
            encode_lineto(cmd)
          when :curve_to
            encode_curveto(cmd)
          end
        end

        # Encode a moveto command
        #
        # Uses rmoveto (relative move) with dx, dy
        # For first move, can optimize to hmoveto/vmoveto if one delta is 0
        #
        # @param cmd [Hash] Command with :x, :y
        def encode_moveto(cmd)
          dx = cmd[:x] - @current_x
          dy = cmd[:y] - @current_y

          if @first_move
            # First move - can optimize
            if dx.zero?
              write_number(dy.round)
              write_operator(:vmoveto)
            elsif dy.zero?
              write_number(dx.round)
              write_operator(:hmoveto)
            else
              write_number(dx.round)
              write_number(dy.round)
              write_operator(:rmoveto)
            end
            @first_move = false
          else
            # Subsequent moves
            write_number(dx.round)
            write_number(dy.round)
            write_operator(:rmoveto)
          end

          @current_x = cmd[:x]
          @current_y = cmd[:y]
        end

        # Encode a lineto command
        #
        # Uses rlineto with dx, dy
        # Could optimize with hlineto/vlineto for horizontal/vertical lines
        #
        # @param cmd [Hash] Command with :x, :y
        def encode_lineto(cmd)
          dx = cmd[:x] - @current_x
          dy = cmd[:y] - @current_y

          # Simple encoding - could optimize for h/v lines
          write_number(dx.round)
          write_number(dy.round)
          write_operator(:rlineto)

          @current_x = cmd[:x]
          @current_y = cmd[:y]
        end

        # Encode a curveto command (cubic Bézier)
        #
        # Uses rrcurveto with 6 relative coordinates:
        # dx1 dy1 dx2 dy2 dx3 dy3
        #
        # @param cmd [Hash] Command with :x1, :y1, :x2, :y2, :x, :y
        def encode_curveto(cmd)
          # Calculate relative coordinates for each control point
          dx1 = cmd[:x1] - @current_x
          dy1 = cmd[:y1] - @current_y

          dx2 = cmd[:x2] - cmd[:x1]
          dy2 = cmd[:y2] - cmd[:y1]

          dx3 = cmd[:x] - cmd[:x2]
          dy3 = cmd[:y] - cmd[:y2]

          # Write operands
          write_number(dx1.round)
          write_number(dy1.round)
          write_number(dx2.round)
          write_number(dy2.round)
          write_number(dx3.round)
          write_number(dy3.round)

          # Write operator
          write_operator(:rrcurveto)

          @current_x = cmd[:x]
          @current_y = cmd[:y]
        end

        # Write a number to the CharString
        #
        # Numbers are encoded in various formats based on their range:
        # - -107 to +107: Single byte (32-246)
        # - -1131 to +1131: Two bytes (247-254 + byte)
        # - -32768 to +32767: Three bytes (28 + 2 bytes)
        # - Otherwise: Five bytes (255 + 4 bytes as 16.16 fixed)
        #
        # @param value [Integer, Float] Number to encode
        def write_number(value)
          # Convert float to integer if it's effectively an integer
          value = value.round if value.is_a?(Float) && value == value.round

          if value.is_a?(Float)
            # Real number - use 5-byte format (16.16 fixed point)
            write_real(value)
          elsif value >= -107 && value <= 107
            # Single byte format: 32-246 represents -107 to +107
            @output.putc(value + 139)
          elsif value >= 108 && value <= 1131
            # Positive two-byte format: 247-250
            adjusted = value - 108
            b0 = 247 + (adjusted / 256)
            b1 = adjusted % 256
            @output.putc(b0)
            @output.putc(b1)
          elsif value >= -1131 && value <= -108
            # Negative two-byte format: 251-254
            adjusted = -value - 108
            b0 = 251 + (adjusted / 256)
            b1 = adjusted % 256
            @output.putc(b0)
            @output.putc(b1)
          elsif value >= -32768 && value <= 32767
            # Three-byte signed integer
            @output.putc(28)
            @output.write([value].pack("s>")) # Signed 16-bit big-endian
          else
            # Five-byte signed integer (stored as 16.16 fixed point)
            write_real(value.to_f)
          end
        end

        # Write a real number (5-byte format)
        #
        # @param value [Float] Real number
        def write_real(value)
          # Convert to 16.16 fixed point
          fixed = (value * 65536.0).round

          @output.putc(255)
          @output.write([fixed].pack("l>")) # Signed 32-bit big-endian
        end

        # Write an operator to the CharString
        #
        # @param operator [Symbol] Operator name
        def write_operator(operator)
          if OPERATORS.key?(operator)
            # Single-byte operator
            @output.putc(OPERATORS[operator])
          elsif TWO_BYTE_OPERATORS.key?(operator)
            # Two-byte operator
            bytes = TWO_BYTE_OPERATORS[operator]
            @output.putc(bytes[0])
            @output.putc(bytes[1])
          else
            raise ArgumentError, "Unknown operator: #{operator}"
          end
        end
      end
    end
  end
end
