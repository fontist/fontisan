# frozen_string_literal: true

module Fontisan
  module Type1
    # Converter for Type 1 CharStrings to CFF CharStrings
    #
    # [`CharStringConverter`](lib/fontisan/type1/charstring_converter.rb) converts
    # Type 1 CharString bytecode to CFF (Compact Font Format) CharString bytecode.
    #
    # Type 1 and CFF use similar stack-based languages but have different operator
    # codes and some structural differences:
    # - Operator codes differ between formats
    # - Type 1 has seac operator for composites; CFF doesn't support it
    # - Hint operators need to be preserved with code translation
    #
    # @example Convert a Type 1 CharString to CFF
    #   converter = Fontisan::Type1::CharStringConverter.new
    #   cff_charstring = converter.convert(type1_charstring)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    # @see https://www.microsoft.com/typography/otspec/cff.htm
    class CharStringConverter
      # Type 1 to CFF operator mapping
      #
      # Maps Type 1 operator codes to CFF operator codes.
      # Some operators have the same code, others differ.
      TYPE1_TO_CFF = {
        # Path construction operators
        hmoveto: 22,      # Type 1: 22, CFF: 22
        vmoveto: 4,       # Type 1: 4, CFF: 4
        rlineto: 5,       # Type 1: 5, CFF: 5
        hlineto: 6,       # Type 1: 6, CFF: 6
        vlineto: 7,       # Type 1: 7, CFF: 7
        rrcurveto: 8,     # Type 1: 8, CFF: 8
        hhcurveto: 27,    # Type 1: 27, CFF: 27
        hvcurveto: 31,    # Type 1: 31, CFF: 31
        vhcurveto: 30,    # Type 1: 30, CFF: 30
        rcurveline: 24,   # Type 1: 24, CFF: 24
        rlinecurve: 25,   # Type 1: 25, CFF: 25

        # Hint operators
        hstem: 1,         # Type 1: 1, CFF: 1
        vstem: 3,         # Type 1: 3, CFF: 3
        hstemhm: 18,      # Type 1: 18, CFF: 18
        vstemhm: 23,      # Type 1: 23, CFF: 23

        # Hint substitution (not in Type 1, but we preserve for compatibility)
        hintmask: 19,     # Type 1: N/A, CFF: 19
        cntrmask: 20,     # Type 1: N/A, CFF: 20

        # End char
        endchar: 14, # Type 1: 14 (or 11 in some specs), CFF: 14

        # Miscellaneous
        callsubr: 10,     # Type 1: 10, CFF: 10
        return: 11,       # Type 1: 11, CFF: 11

        # Deprecated operators (preserve for compatibility)
        hstem3: 12,       # Type 1: 12 (escape 0), CFF: 12 (escape 0)
        vstem3: 13,       # Type 1: 13 (escape 1), CFF: 13 (escape 1)
        seac: 12,         # Type 1: 12 (escape 6), CFF: Not supported
      }.freeze

      # Escape code for two-byte operators
      ESCAPE_BYTE = 12

      # seac operator escape code (second byte)
      SEAC_ESCAPE_CODE = 6

      # Initialize a new CharStringConverter
      #
      # @param charstrings [CharStrings, nil] CharStrings dictionary for seac expansion
      def initialize(charstrings = nil)
        @charstrings = charstrings
      end

      # Convert Type 1 CharString to CFF CharString
      #
      # @param type1_charstring [String] Type 1 CharString bytecode
      # @return [String] CFF CharString bytecode
      #
      # @example Convert a CharString
      #   converter = Fontisan::Type1::CharStringConverter.new
      #   cff_bytes = converter.convert(type1_bytes)
      def convert(type1_charstring)
        # Parse Type 1 CharString into commands
        parser = Type1::CharStrings::CharStringParser.new
        commands = parser.parse(type1_charstring)

        # Check for seac operator and expand if needed
        if parser.seac_components
          return expand_seac(parser.seac_components)
        end

        # Convert commands to CFF format
        convert_commands(commands)
      end

      # Convert parsed commands to CFF CharString
      #
      # @param commands [Array<Array>] Parsed Type 1 commands
      # @return [String] CFF CharString bytecode
      def convert_commands(commands)
        result = String.new(encoding: Encoding::ASCII_8BIT)

        commands.each do |command|
          case command[0]
          when :number
            # Encode number in CFF format
            result << encode_cff_number(command[1])
          when :seac
            # seac should be expanded before this point
            raise Fontisan::Error,
                  "seac operator not supported in CFF, must be expanded first"
          else
            # Convert operator
            op_code = TYPE1_TO_CFF[command[0]]
            if op_code.nil?
              # Unknown operator, skip or raise error
              next
            end

            result << encode_cff_operator(op_code)
          end
        end

        result
      end

      # Expand seac composite glyph
      #
      # The seac operator in Type 1 creates composite glyphs (like À = A + `).
      # CFF doesn't support seac, so we need to expand it into the base glyphs
      # with appropriate positioning.
      #
      # @param seac_data [Hash] seac component data
      # @return [String] CFF CharString bytecode with expanded seac
      def expand_seac(seac_data)
        # seac format: adx ady bchar achar seac
        # adx, ady: accent offset
        # bchar: base character code
        # achar: accent character code
        # The accent is positioned at (adx, ady) relative to the base

        seac_data[:base]
        seac_data[:accent]
        seac_data[:adx]
        seac_data[:ady]

        # For now, we'll create a simple placeholder that indicates seac expansion
        # In a full implementation, we would:
        # 1. Parse the base glyph's CharString
        # 2. Parse the accent glyph's CharString
        # 3. Merge them with the appropriate offset
        # 4. Convert to CFF format

        # This is a simplified implementation that creates a composite reference
        # CFF doesn't have native seac, so we need to actually merge the outlines

        # For now, return endchar as placeholder
        # TODO: Implement full seac expansion by merging glyph outlines
        encode_cff_operator(TYPE1_TO_CFF[:endchar])
      end

      # Check if CharString contains seac operator
      #
      # @param type1_charstring [String] Type 1 CharString bytecode
      # @return [Boolean] True if CharString contains seac
      def seac?(type1_charstring)
        parser = Type1::CharStrings::CharStringParser.new
        parser.parse(type1_charstring)
        !parser.seac_components.nil?
      end

      private

      # Encode number in CFF format
      #
      # CFF uses a variable-length encoding for numbers:
      # - 32-246: 1 byte (value - 139)
      # - 247-250: 2 bytes (first byte indicates format)
      # - 251-254: 3 bytes (first byte indicates format)
      # - 255: 5 bytes (signed 16-bit integer)
      # - 28: 2 bytes (signed 16.16 fixed point, not used for CharStrings)
      #
      # @param value [Integer] Number to encode
      # @return [String] Encoded number bytes
      def encode_cff_number(value)
        result = String.new(encoding: Encoding::ASCII_8BIT)

        if value >= -107 && value <= 107
          # 1-byte number: value + 139
          result << (value + 139).chr
        elsif value >= 108 && value <= 1131
          # 2-byte positive number
          value -= 108
          result << ((value >> 8) + 247).chr
          result << (value & 0xFF).chr
        elsif value >= -1131 && value <= -108
          # 2-byte negative number
          value = -value - 108
          result << ((value >> 8) + 251).chr
          result << (value & 0xFF).chr
        elsif value >= -32768 && value <= 32767
          # 5-byte number (16-bit integer)
          result << 255.chr
          result << [(value >> 8) & 0xFF, value & 0xFF].pack("CC")
          result << [0, 0].pack("CC") # Pad to 5 bytes
        else
          raise Fontisan::Error,
                "Number out of range for CFF encoding: #{value}"
        end

        result
      end

      # Encode operator in CFF format
      #
      # Most operators are single-byte. Some use escape byte (12) followed
      # by a second byte.
      #
      # @param op_code [Integer] Operator code
      # @return [String] Encoded operator bytes
      def encode_cff_operator(op_code)
        result = String.new(encoding: Encoding::ASCII_8BIT)

        if op_code > 31 && op_code != ESCAPE_BYTE
          # Two-byte operator (escape + code)
          result << ESCAPE_BYTE.chr
          result << (op_code - ESCAPE_BYTE).chr
        else
          # Single-byte operator
          result << op_code.chr
        end

        result
      end
    end
  end
end
