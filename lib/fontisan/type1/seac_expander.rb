# frozen_string_literal: true

module Fontisan
  module Type1
    # Error raised when a seac reference cannot be resolved (the referenced
    # glyph is missing, or a cycle is detected in nested seac).
    class SeacReferenceError < Fontisan::Error; end

    # Expands Type 1 seac composite glyphs into base + accent outlines
    #
    # [`SeacExpander`](lib/fontisan/type1/seac_expander.rb) handles the
    # decomposition of Type 1 composite glyphs that use the `seac` operator.
    # The seac operator combines two glyphs (a base character and an accent)
    # with a positioning offset, which must be decomposed for CFF conversion.
    #
    # Supports nested seac: if a base or accent glyph is itself a seac
    # composite, it is recursively expanded. Cycles are detected and raise
    # {SeacReferenceError}.
    #
    # The seac operator format is:
    # ```
    # seac asb adx ady bchar achar
    # ```
    #
    # Where:
    # - `asb`: Accent side bearing (not used in decomposition)
    # - `adx`: X offset for accent placement
    # - `ady`: Y offset for accent placement
    # - `bchar`: Character code of base glyph
    # - `achar`: Character code of accent glyph
    #
    # @example Decompose a seac composite
    #   expander = Fontisan::Type1::SeacExpander.new(charstrings, private_dict)
    #   decomposed = expander.decompose("Agrave")
    #   # => Returns merged outline of base 'A' + accent 'grave'
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class SeacExpander
      MAX_DEPTH = 16

      # @return [CharStrings] Type 1 CharStrings dictionary
      attr_reader :charstrings

      # @return [PrivateDict] Private dictionary for hinting
      attr_reader :private_dict

      # Initialize a new SeacExpander
      #
      # @param charstrings [CharStrings] Type 1 CharStrings dictionary
      # @param private_dict [PrivateDict] Private dictionary for context
      def initialize(charstrings, private_dict)
        @charstrings = charstrings
        @private_dict = private_dict
      end

      # Decompose a seac composite glyph into base + accent outlines.
      # Handles nested seac recursively.
      #
      # @param glyph_name [String] Name of the composite glyph to decompose
      # @return [String, nil] Decomposed CharString bytecode, or nil if not a seac composite
      # @raise [SeacReferenceError] If base or accent glyphs are not found,
      #   or if a cycle is detected
      def decompose(glyph_name)
        decompose_with_visited(glyph_name, Set.new)
      end

      # Check if a glyph is a seac composite
      #
      # @param glyph_name [String] Glyph name to check
      # @return [Boolean] True if the glyph uses seac operator
      def composite?(glyph_name)
        @charstrings.composite?(glyph_name)
      end

      # Get all seac composite glyphs in the font
      #
      # @return [Array<String>] List of composite glyph names
      def composite_glyphs
        @charstrings.glyph_names.select { |name| composite?(name) }
      end

      private

      # Recursive decomposition with cycle detection via +visited+ set.
      def decompose_with_visited(glyph_name, visited)
        return nil unless composite?(glyph_name)

        if visited.include?(glyph_name)
          raise SeacReferenceError,
                "Cycle detected in seac references: #{visited.to_a.join(' → ')} → #{glyph_name}"
        end

        if visited.size >= MAX_DEPTH
          raise SeacReferenceError,
                "seac nesting depth exceeds #{MAX_DEPTH} at #{glyph_name}"
        end

        visited_next = visited.dup.add(glyph_name)
        components = @charstrings.components_for(glyph_name)

        base_name = resolve_char_code(components[:base], "base", glyph_name)
        accent_name = resolve_char_code(components[:accent], "accent", glyph_name)

        base_commands = resolve_glyph_commands(base_name, visited_next)
        accent_commands = resolve_glyph_commands(accent_name, visited_next)
        accent_commands = transform_commands(accent_commands, components[:adx],
                                             components[:ady])
        merged = merge_outline_commands(base_commands, accent_commands)
        generate_charstring(merged)
      end

      # Resolve a char code to a glyph name via the font's encoding.
      def resolve_char_code(char_code, role, parent)
        name = @charstrings.encoding[char_code]
        return name if name

        raise SeacReferenceError,
              "#{role} glyph for char code #{char_code} (in #{parent}) not found in encoding"
      end

      # Get outline commands for a glyph, recursively expanding nested seac.
      def resolve_glyph_commands(glyph_name, visited)
        charstring = @charstrings[glyph_name]
        if charstring.nil?
          raise SeacReferenceError,
                "CharString not found for glyph #{glyph_name}"
        end

        if composite?(glyph_name)
          nested = decompose_with_visited(glyph_name, visited)
          parse_charstring_to_commands(nested)
        else
          parse_charstring_to_commands(charstring)
        end
      end

      # Parse Type 1 CharString into drawing commands
      #
      # Converts Type 1 CharString bytecode into a list of drawing commands
      # that can be manipulated and transformed.
      #
      # @param charstring [String] Binary CharString data
      # @return [Array<Hash>] Array of command hashes
      def parse_charstring_to_commands(charstring)
        parser = CharStrings::CharStringParser.new(@private_dict)
        parser.parse(charstring)
        # Preprocess to combine numbers with operators
        combined_commands = combine_numbers_with_operators(parser.commands)
        commands_to_outline(combined_commands)
      end

      # Combine separate number commands with their operators
      #
      # The CharStringParser produces commands like [[:number, 100], [:number, 0], [:hsbw]]
      # This method combines them into [[:hsbw, 100, 0]]
      #
      # @param commands [Array] Parser commands
      # @return [Array] Combined commands
      def combine_numbers_with_operators(commands)
        result = []
        number_stack = []

        commands.each do |cmd|
          if cmd[0] == :number
            number_stack << cmd[1]
          elsif cmd[0] == :seac
            # seac is special - it uses the number stack for components
            result << cmd
            parse_seac_from_stack(result, number_stack)
          else
            # Operator - pop required numbers from stack
            operator = cmd[0]
            args = get_args_for_operator(operator, number_stack)
            result << [operator, *args] if args
          end
        end

        result
      end

      # Get arguments for an operator from the number stack
      #
      # @param operator [Symbol] Operator symbol
      # @param stack [Array] Number stack
      # @return [Array, nil] Arguments or nil if operator unknown
      def get_args_for_operator(operator, stack)
        case operator
        when :hsbw
          # hsbw takes 2 args: sbw, width
          stack.pop(2).reverse
        when :sbw
          # sbw takes 3 args: sbw, wy, wx
          stack.pop(3).reverse
        when :rmoveto
          # rmoveto takes 2 args: dy, dx
          stack.pop(2).reverse
        when :hmoveto
          # hmoveto takes 1 arg: dx
          stack.pop(1)
        when :vmoveto
          # vmoveto takes 1 arg: dy
          stack.pop(1)
        when :rlineto
          # rlineto takes 2 args: dy, dx
          stack.pop(2).reverse
        when :hlineto
          # hlineto takes 1 arg: dx
          stack.pop(1)
        when :vlineto
          # vlineto takes 1 arg: dy
          stack.pop(1)
        when :rrcurveto
          # rrcurveto takes 6 args: dy3, dx3, dy2, dx2, dy1, dx1
          stack.pop(6).reverse
        when :vhcurveto, :hvcurveto
          # vhcurveto/hvcurveto take 4 args
          stack.pop(4).reverse
        when :hstem, :vstem, :callsubr, :return, :endchar
          # These operators don't need args for outline conversion
          []
        else
          # Unknown operator - return nil
          nil
        end
      end

      # Parse seac components from number stack
      #
      # @param result [Array] Result array to append to
      # @param stack [Array] Number stack
      def parse_seac_from_stack(result, stack)
        return if stack.length < 5

        # Last 5 numbers are: asb, adx, ady, bchar, achar
        args = stack.pop(5).reverse
        result.last[1] = args[1] # adx
        result.last[2] = args[2] # ady
        result.last[3] = args[3] # bchar
        result.last[4] = args[4] # achar
      end

      # Convert parser commands to outline format
      #
      # @param commands [Array] Parser command format [type, *args]
      # @return [Array<Hash>] Outline command format
      def commands_to_outline(commands)
        outline_commands = []
        x = 0
        y = 0

        commands.each do |cmd|
          case cmd[0]
          when :hsbw
            # hsbw x0 sbw: Set horizontal width and left sidebearing
            # This is usually the first command in a CharString
            x = cmd[1]
            y = 0
            outline_commands << { type: :move_to, x: x, y: y }
          when :sbw
            # sbw sbw x0 sbw: Set width and side bearings (vertical)
            y = cmd[1]
            x = cmd[2]
            outline_commands << { type: :move_to, x: x, y: y }
          when :rmoveto
            # rmoveto dx dy: Relative move to
            x += cmd[1]
            y += cmd[2]
            outline_commands << { type: :line_to, x: x, y: y }
          when :hmoveto
            # hmoveto dx: Horizontal move to
            x += cmd[1]
            outline_commands << { type: :line_to, x: x, y: y }
          when :vmoveto
            # vmoveto dy: Vertical move to
            y += cmd[1]
            outline_commands << { type: :line_to, x: x, y: y }
          when :rlineto
            # rlineto dx dy: Relative line to
            x += cmd[1]
            y += cmd[2]
            outline_commands << { type: :line_to, x: x, y: y }
          when :hlineto
            # hlineto dx: Horizontal line to
            x += cmd[1]
            outline_commands << { type: :line_to, x: x, y: y }
          when :vlineto
            # vlineto dy: Vertical line to
            y += cmd[1]
            outline_commands << { type: :line_to, x: x, y: y }
          when :rrcurveto
            # rrcurveto dx1 dy1 dx2 dy2 dx3 dy3: Relative curved line to
            # This is a quadratic curve in Type 1
            # Convert to our outline format (quadratic)
            dx1, dy1, dx2, dy2, dx3, dy3 = cmd[1..6]
            control_x = x + dx1
            control_y = y + dy1
            x + dx1 + dx2
            y + dy1 + dy2
            end_x = x + dx1 + dx2 + dx3
            end_y = y + dy1 + dy2 + dy3

            outline_commands << {
              type: :quad_to,
              cx: control_x,
              cy: control_y,
              x: end_x,
              y: end_y,
            }
            x = end_x
            y = end_y
          when :vhcurveto, :hvcurveto
            # vhcurveto: Vertical-to-horizontal curve
            # hvcurveto: Horizontal-to-vertical curve
            # These are also quadratic curves
            # For now, treat as simple curves
            handle_curve_command(outline_commands, cmd, x, y)
            x = outline_commands.last[:x]
            y = outline_commands.last[:y]
          when :endchar
            # End of CharString
            break
          when :number
            # Number - skip, consumed by operators
            nil
          else
            # Unknown command - skip
            nil
          end
        end

        outline_commands
      end

      # Handle curve commands (vhcurveto, hvcurveto)
      #
      # @param commands [Array] Command list to append to
      # @param cmd [Array] The curve command
      # @param x [Integer] Current X position
      # @param y [Integer] Current Y position
      def handle_curve_command(commands, cmd, x, y)
        # Simplified handling - treat as quadratic curve
        # vhcurveto: dy1 dx2 dy2 dx3
        # hvcurveto: dx1 dy2 dx3 dy3
        if cmd[0] == :vhcurveto
          dy1, dx2, dy2, = cmd[1..4]
          control_x = x
          control_y = y + dy1
          end_x = x + dx2
          end_y = y + dy1 + dy2
        else
          dx1, dy2, _, dy3 = cmd[1..4]
          control_x = x + dx1
          control_y = y
          end_x = x + dx1 + dx2
          end_y = y + dy2 + dy3
        end

        commands << {
          type: :quad_to,
          cx: control_x,
          cy: control_y,
          x: end_x,
          y: end_y,
        }
      end

      # Transform outline commands by translation
      #
      # @param commands [Array<Hash>] Outline commands
      # @param dx [Integer] X offset
      # @param dy [Integer] Y offset
      # @return [Array<Hash>] Transformed commands
      def transform_commands(commands, dx, dy)
        return commands if dx.zero? && dy.zero?

        commands.map do |cmd|
          case cmd[:type]
          when :move_to, :line_to
            { type: cmd[:type], x: cmd[:x] + dx, y: cmd[:y] + dy }
          when :quad_to
            {
              type: :quad_to,
              cx: cmd[:cx] + dx,
              cy: cmd[:cy] + dy,
              x: cmd[:x] + dx,
              y: cmd[:y] + dy,
            }
          when :curve_to
            {
              type: :curve_to,
              cx1: cmd[:cx1] + dx,
              cy1: cmd[:cy1] + dy,
              cx2: cmd[:cx2] + dx,
              cy2: cmd[:cy2] + dy,
              x: cmd[:x] + dx,
              y: cmd[:y] + dy,
            }
          else
            cmd # close_path, etc. pass through
          end
        end
      end

      # Merge base and accent outline commands
      #
      # Combines two outline sequences into one. The accent outline is
      # appended to the base outline with proper contour separation.
      #
      # @param base_commands [Array<Hash>] Base glyph commands
      # @param accent_commands [Array<Hash>] Accent glyph commands
      # @return [Array<Hash>] Merged commands
      def merge_outline_commands(base_commands, accent_commands)
        # Remove the final close_path from base (if any)
        # Then append accent commands
        merged = base_commands.dup

        # If base ends with close_path, remove it (accent will have its own)
        merged.pop if merged.last && merged.last[:type] == :close_path

        # Add accent commands
        merged.concat(accent_commands)

        merged
      end

      # Generate CharString bytecode from outline commands
      #
      # Converts outline commands back to Type 1 CharString format.
      # This is a simplified implementation that handles common cases.
      #
      # @param commands [Array<Hash>] Outline commands
      # @return [String] Binary CharString data
      def generate_charstring(commands)
        return "" if commands.empty?

        charstring = String.new(encoding: Encoding::ASCII_8BIT)

        x = 0
        y = 0

        commands.each do |cmd|
          case cmd[:type]
          when :move_to
            # Use hsbw to set initial position
            dx = cmd[:x] - x
            # hsbw is a two-byte operator: 12 34
            charstring << encode_number(dx) # sbw value
            charstring << encode_number(0) # width (always 0 for decomposed glyphs)
            charstring << 12  # First byte of two-byte operator
            charstring << 34  # Second byte - hsbw
            x = cmd[:x]
            y = cmd[:y]
          when :line_to
            dx = cmd[:x] - x
            dy = cmd[:y] - y
            if dx != 0 && dy != 0
              charstring << encode_number(dx)
              charstring << encode_number(dy)
              charstring << 5 # rlineto
            elsif dx != 0
              charstring << encode_number(dx)
              charstring << 6 # hlineto
            elsif dy != 0
              charstring << encode_number(dy)
              charstring << 7 # vlineto
            end
            x = cmd[:x]
            y = cmd[:y]
          when :quad_to
            # rrcurveto: dx1 dy1 dx2 dy2 dx3 dy3
            dx1 = cmd[:cx] - x
            dy1 = cmd[:cy] - y
            # For quadratic curves, we need to convert to cubic (Type 1 rrcurveto)
            # This is a simplified conversion
            anchor_dx = (cmd[:x] - x) / 2 - dx1 / 2
            anchor_dy = (cmd[:y] - y) / 2 - dy1 / 2
            end_dx = (cmd[:x] - x) - dx1 - anchor_dx
            end_dy = (cmd[:y] - y) - dy1 - anchor_dy

            charstring << encode_number(dx1)
            charstring << encode_number(dy1)
            charstring << encode_number(anchor_dx)
            charstring << encode_number(anchor_dy)
            charstring << encode_number(end_dx)
            charstring << encode_number(end_dy)
            charstring << 8 # rrcurveto
            x = cmd[:x]
            y = cmd[:y]
          end
        end

        # Add endchar
        charstring << 14

        charstring
      end

      # Encode integer for Type 1 CharString
      #
      # Type 1 CharStrings use a variable-length integer encoding:
      # - Numbers from -107 to 107: single byte (byte + 139)
      # - Larger numbers: escaped with 255, then 2-byte value
      #
      # @param num [Integer] Number to encode
      # @return [String] Encoded bytes
      def encode_number(num)
        if num >= -107 && num <= 107
          [num + 139].pack("C*")
        else
          # Use escape sequence (255) followed by 2-byte signed integer
          num += 32768 if num.negative?
          [255, num % 256, num >> 8].pack("C*")
        end
      end
    end
  end
end
