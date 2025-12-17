# frozen_string_literal: true

require_relative "../models/hint"

module Fontisan
  module Hints
    # Extracts rendering hints from PostScript/CFF CharString data
    #
    # PostScript Type 1 and CFF fonts embed hints directly in the
    # CharString data as operators. This extractor parses CharString
    # sequences to identify and extract hint operators.
    #
    # **Supported PostScript Hint Operators:**
    #
    # - hstem/vstem - Horizontal/vertical stem hints
    # - hstem3/vstem3 - Multiple stem hints
    # - hintmask - Hint replacement masks
    # - cntrmask - Counter control masks
    #
    # @example Extract hints from a CharString
    #   extractor = PostScriptHintExtractor.new
    #   hints = extractor.extract(charstring)
    class PostScriptHintExtractor
      # CFF CharString operators
      HSTEM = 1
      VSTEM = 3
      HINTMASK = 19
      CNTRMASK = 20
      HSTEM3 = 12 << 8 | 2
      VSTEM3 = 12 << 8 | 1

      # Extract hints from CFF CharString
      #
      # @param charstring [CharString, String] CFF CharString object or bytes
      # @return [Array<Hint>] Extracted hints
      def extract(charstring)
        return [] if charstring.nil?

        # Get CharString bytes
        bytes = if charstring.respond_to?(:data)
                  charstring.data
                elsif charstring.respond_to?(:bytes)
                  charstring.bytes
                elsif charstring.is_a?(String)
                  charstring.bytes
                else
                  return []
                end

        return [] if bytes.empty?

        parse_charstring(bytes)
      end

      private

      # Parse CharString bytes to extract hints
      #
      # @param bytes [Array<Integer>] CharString bytes
      # @return [Array<Hint>] Extracted hints
      def parse_charstring(bytes)
        hints = []
        stack = []
        i = 0

        while i < bytes.length
          byte = bytes[i]

          if operator?(byte)
            # Process operator
            operator = if byte == 12
                        # Two-byte operator
                        i += 1
                        (12 << 8) | bytes[i]
                      else
                        byte
                      end

            hint = process_operator(operator, stack)
            hints << hint if hint

            # Clear stack after operator
            stack.clear
            i += 1
          else
            # Number - push to stack
            num, consumed = decode_number(bytes, i)
            stack << num if num
            i += consumed
          end
        end

        hints
      end

      # Check if byte is an operator
      #
      # @param byte [Integer] Byte value
      # @return [Boolean] True if operator
      def operator?(byte)
        byte <= 31 || byte == 255
      end

      # Decode a number from CharString
      #
      # @param bytes [Array<Integer>] CharString bytes
      # @param index [Integer] Starting position
      # @return [Array<Integer, Integer>] [number, bytes_consumed]
      def decode_number(bytes, index)
        byte = bytes[index]
        return [nil, 1] if byte.nil?

        case byte
        when 28
          # 3-byte signed integer
          if index + 2 < bytes.length
            num = (bytes[index + 1] << 8) | bytes[index + 2]
            num = num - 65536 if num > 32767
            [num, 3]
          else
            [nil, 1]
          end
        when 32..246
          # Single byte integer
          [byte - 139, 1]
        when 247..250
          # Positive 2-byte integer
          if index + 1 < bytes.length
            num = (byte - 247) * 256 + bytes[index + 1] + 108
            [num, 2]
          else
            [nil, 1]
          end
        when 251..254
          # Negative 2-byte integer
          if index + 1 < bytes.length
            num = -(byte - 251) * 256 - bytes[index + 1] - 108
            [num, 2]
          else
            [nil, 1]
          end
        when 255
          # 5-byte signed integer
          if index + 4 < bytes.length
            num = (bytes[index + 1] << 24) | (bytes[index + 2] << 16) |
                  (bytes[index + 3] << 8) | bytes[index + 4]
            num = num - 4294967296 if num > 2147483647
            [num, 5]
          else
            [nil, 1]
          end
        else
          [nil, 1]
        end
      end

      # Process hint operator and create Hint object
      #
      # @param operator [Integer] Operator code
      # @param stack [Array<Integer>] Current operand stack
      # @return [Hint, nil] Hint object if operator is a hint
      def process_operator(operator, stack)
        case operator
        when HSTEM
          # Horizontal stem hint
          extract_stem_hint(stack, :horizontal)

        when VSTEM
          # Vertical stem hint
          extract_stem_hint(stack, :vertical)

        when HSTEM3
          # Multiple horizontal stems
          extract_stem3_hint(stack, :horizontal)

        when VSTEM3
          # Multiple vertical stems
          extract_stem3_hint(stack, :vertical)

        when HINTMASK
          # Hint replacement mask
          Models::Hint.new(
            type: :hint_replacement,
            data: { mask: stack.dup },
            source_format: :postscript
          )

        when CNTRMASK
          # Counter control mask
          Models::Hint.new(
            type: :counter,
            data: { zones: stack.dup },
            source_format: :postscript
          )

        else
          nil
        end
      end

      # Extract stem hint from stack
      #
      # @param stack [Array<Integer>] Operand stack
      # @param orientation [Symbol] :horizontal or :vertical
      # @return [Hint] Stem hint
      def extract_stem_hint(stack, orientation)
        # Stack should have pairs of [position, width]
        return nil if stack.empty? || stack.length < 2

        # Take first pair
        position = stack[0]
        width = stack[1]

        Models::Hint.new(
          type: :stem,
          data: {
            position: position,
            width: width,
            orientation: orientation
          },
          source_format: :postscript
        )
      end

      # Extract stem3 hint from stack
      #
      # @param stack [Array<Integer>] Operand stack
      # @param orientation [Symbol] :horizontal or :vertical
      # @return [Hint] Stem3 hint
      def extract_stem3_hint(stack, orientation)
        # Stack should have 6 values: 3 pairs of [position, width]
        return nil if stack.length < 6

        stems = []
        (0..2).each do |i|
          pos_idx = i * 2
          stems << {
            position: stack[pos_idx],
            width: stack[pos_idx + 1]
          }
        end

        Models::Hint.new(
          type: :stem3,
          data: {
            stems: stems,
            orientation: orientation
          },
          source_format: :postscript
        )
      end
    end
  end
end
