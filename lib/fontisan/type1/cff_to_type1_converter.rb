# frozen_string_literal: true

module Fontisan
  module Type1
    # Converter for CFF CharStrings to Type 1 CharStrings
    #
    # [`CffToType1Converter`](lib/fontisan/type1/cff_to_type1_converter.rb) converts
    # CFF (Compact Font Format) Type 2 CharStrings to Type 1 CharStrings.
    #
    # CFF and Type 1 use similar stack-based languages but have different operator
    # codes and some structural differences:
    # - Operator codes differ between formats
    # - Type 1 uses hsbw/sbw for width selection; CFF uses initial operand
    # - Hint operators need to be preserved with code translation
    #
    # @example Convert a CFF CharString to Type 1
    #   converter = Fontisan::Type1::CffToType1Converter.new
    #   type1_charstring = converter.convert(cff_charstring)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    # @see https://www.microsoft.com/typography/otspec/cff.htm
    class CffToType1Converter
      # CFF to Type 1 operator mapping
      #
      # Maps CFF operator codes to Type 1 operator codes.
      # Most operators are the same, but some differ.
      CFF_TO_TYPE1 = {
        # Path construction operators
        hmoveto: 22,      # CFF: 22, Type 1: 22
        vmoveto: 4,       # CFF: 4, Type 1: 4
        rlineto: 5,       # CFF: 5, Type 1: 5
        hlineto: 6,       # CFF: 6, Type 1: 6
        vlineto: 7,       # CFF: 7, Type 1: 7
        rrcurveto: 8,     # CFF: 8, Type 1: 8
        hhcurveto: 27,    # CFF: 27, Type 1: 27
        hvcurveto: 31,    # CFF: 31, Type 1: 31
        vhcurveto: 30,    # CFF: 30, Type 1: 30
        rcurveline: 24,   # CFF: 24, Type 1: 24
        rlinecurve: 25,   # CFF: 25, Type 1: 25

        # Hint operators
        hstem: 1,         # CFF: 1, Type 1: 1
        vstem: 3,         # CFF: 3, Type 1: 3
        hstemhm: 18,      # CFF: 18, Type 1: 18
        vstemhm: 23,      # CFF: 23, Type 1: 23

        # Hint substitution (preserve for compatibility)
        hintmask: 19,     # CFF: 19, Type 1: Not supported (skip)
        cntrmask: 20,     # CFF: 20, Type 1: Not supported (skip)

        # End char
        endchar: 14, # CFF: 14, Type 1: 14

        # Miscellaneous
        callsubr: 10,     # CFF: 10, Type 1: 10
        return: 11,       # CFF: 11, Type 1: 11
        rmoveto: 21,      # CFF: 21, Type 1: 21
      }.freeze

      # Escape code for two-byte operators
      ESCAPE_BYTE = 12

      # Initialize a new CffToType1Converter
      #
      # @param nominal_width [Integer] Nominal width from CFF Private dict (default: 0)
      # @param default_width [Integer] Default width from CFF Private dict (default: 0)
      def initialize(nominal_width: 0, default_width: 0)
        @nominal_width = nominal_width
        @default_width = default_width
      end

      # Convert CFF CharString to Type 1 CharString
      #
      # Takes binary CFF CharString data and converts it to Type 1 format.
      #
      # @param cff_charstring [String] CFF CharString bytecode
      # @param private_dict [Hash] CFF Private dict for context (optional)
      # @return [String] Type 1 CharString bytecode
      #
      # @example Convert a CharString
      #   converter = Fontisan::Type1::CffToType1Converter.new
      #   type1_bytes = converter.convert(cff_bytes)
      def convert(cff_charstring, private_dict: {})
        # Parse CFF CharString into operations
        parser = Tables::Cff::CharStringParser.new(cff_charstring,
                                                   stem_count: private_dict[:stem_count].to_i)
        operations = parser.parse

        # Extract width from operations (CFF spec: odd stack before first move = width)
        width = extract_width(operations)

        # Convert operations to Type 1 format
        convert_operations(operations, width)
      end

      # Extract width from CFF operations
      #
      # In CFF, if there's an odd number of arguments before the first move
      # operator (rmoveto, hmoveto, vmoveto, rcurveline, rrcurveline, vvcurveto,
      # hhcurveto), the first argument is the width.
      #
      # @param operations [Array<Hash>] Parsed CFF operations
      # @return [Integer, nil] Width value or nil if using default
      def extract_width(operations)
        return @default_width if operations.empty?

        # Find first move operator
        first_move_idx = operations.index do |op|
          %i[rmoveto hmoveto vmoveto rcurveline rrcurveline vvcurveto
             hhcurveto].include?(op[:name])
        end

        return @default_width unless first_move_idx

        # Count operands before first move
        operand_count = operations[0...first_move_idx].sum do |op|
          op[:operands]&.length || 0
        end

        # If odd, first operand of first move is width
        if operand_count.odd?
          first_move = operations[first_move_idx]
          if first_move[:operands] && !first_move[:operands].empty?
            return first_move[:operands].first
          end
        end

        @default_width
      end

      # Convert parsed CFF operations to Type 1 CharString
      #
      # @param operations [Array<Hash>] Parsed CFF operations
      # @param width [Integer, nil] Glyph width from CFF CharString
      # @return [String] Type 1 CharString bytecode
      def convert_operations(operations, width = nil)
        result = String.new(encoding: Encoding::ASCII_8BIT)

        # Determine width: use provided width or default/nominal
        glyph_width = width || @default_width

        # Add hsbw (horizontal sidebearing and width) at start
        # This is the standard width operator for horizontal fonts
        result << encode_number(0) # left sidebearing (usually 0 for CFF)
        result << encode_number(glyph_width)
        result << ESCAPE_BYTE
        result << 34 # hsbw operator (two-byte: 12 34)

        x = 0
        y = 0
        first_move = true
        skip_first_operand = false

        # Check if width was extracted (odd stack before first move)
        if width && operations.any?
          # Count operands before first move to determine if width was in stack
          first_move_idx = operations.index do |op|
            %i[rmoveto hmoveto vmoveto rcurveline rrcurveline vvcurveto
               hhcurveto].include?(op[:name])
          end

          if first_move_idx
            operand_count = operations[0...first_move_idx].sum do |op|
              op[:operands]&.length || 0
            end

            skip_first_operand = operand_count.odd?
          end
        end

        operations.each do |op|
          case op[:name]
          when :hstem, :vstem, :hstemhm, :vstemhm
            # Hint operators - preserve
            op[:operands].each { |val| result << encode_number(val) }
            result << CFF_TO_TYPE1[op[:name]]
          when :rmoveto
            # rmoveto dx dy (or width dx dy if first move with odd stack)
            operands = op[:operands]
            if first_move && skip_first_operand && !operands.empty?
              # Skip first operand (it was the width)
              operands = operands[1..]
              skip_first_operand = false
            end

            if operands.length >= 2
              dx = operands[0]
              dy = operands[1]
              x += dx
              y += dy
              result << encode_number(dx)
              result << encode_number(dy)
              result << 21 # rmoveto
            elsif operands.length == 1
              # Only dy (hmoveto/vmoveto style)
              result << encode_number(operands.first)
              result << 4 # vmoveto (closest approximation)
            end
            first_move = false
          when :hmoveto
            # hmoveto dx (or width dx if first move)
            operands = op[:operands]
            if first_move && skip_first_operand && !operands.empty?
              operands = [operands[0]] if operands.length > 1
              skip_first_operand = false
            end

            dx = operands.first
            x += dx if dx
            result << encode_number(dx)
            result << 22 # hmoveto
            first_move = false
          when :vmoveto
            # vmoveto dy
            dy = op[:operands].first
            y += dy if dy
            result << encode_number(dy)
            result << 4 # vmoveto
            first_move = false
          when :rlineto
            # rlineto dx dy
            dx, dy = op[:operands]
            x += dx
            y += dy
            result << encode_number(dx)
            result << encode_number(dy)
            result << 5 # rlineto
            first_move = false
          when :hlineto
            # hlineto dx
            dx = op[:operands].first
            x += dx
            result << encode_number(dx)
            result << 6 # hlineto
            first_move = false
          when :vlineto
            # vlineto dy
            dy = op[:operands].first
            y += dy
            result << encode_number(dy)
            result << 7 # vlineto
            first_move = false
          when :rrcurveto
            # rrcurveto dx1 dy1 dx2 dy2 dx3 dy3
            dx1, dy1, dx2, dy2, dx3, dy3 = op[:operands]
            x += dx1 + dx2 + dx3
            y += dy1 + dy2 + dy3
            [dx1, dy1, dx2, dy2, dx3, dy3].each do |val|
              result << encode_number(val)
            end
            result << 8 # rrcurveto
            first_move = false
          when :hhcurveto, :hvcurveto, :vhcurveto
            # Flexible curve operators
            op[:operands].each { |val| result << encode_number(val) }
            result << CFF_TO_TYPE1[op[:name]]
            first_move = false
          when :rcurveline, :rlinecurve
            # Flexible curve operators
            op[:operands].each { |val| result << encode_number(val) }
            result << CFF_TO_TYPE1[op[:name]]
            first_move = false
          when :callsubr, :return, :endchar
            # Control operators
            result << CFF_TO_TYPE1[op[:name]]
            first_move = false
          when :hintmask, :cntrmask
            # Hint mask operators - Type 1 doesn't support these
            # Skip them
            first_move = false
          when :shortint
            # Short integer push - handled by operand encoding
            first_move = false
          else
            # Unknown operator - skip
            first_move = false
          end
        end

        # Add endchar
        result << 14

        result
      end

      private

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
          [num + 139].pack("C")
        else
          # Use escape sequence (255) followed by 2-byte signed integer
          num += 32768 if num.negative?
          [255, num % 256, num >> 8].pack("C*")
        end
      end
    end
  end
end
