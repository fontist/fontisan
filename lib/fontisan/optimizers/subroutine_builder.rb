# frozen_string_literal: true

module Fontisan
  module Optimizers
    # Builds CFF subroutines from analyzed patterns. Converts pattern byte
    # sequences into valid CFF CharStrings with return operators, calculates
    # bias values, and generates callsubr operators for pattern replacement.
    #
    # @example Basic usage
    #   patterns = analyzer.analyze(charstrings)
    #   builder = SubroutineBuilder.new(patterns, type: :local)
    #   subroutines = builder.build
    #   bias = builder.bias
    #   call = builder.create_call(0)  # Call first subroutine
    #
    # @see docs/SUBROUTINE_ARCHITECTURE.md
    class SubroutineBuilder
      # CFF return operator
      RETURN_OPERATOR = "\x0b"

      # CFF callsubr operator
      CALLSUBR_OPERATOR = "\x0a"

      # Initialize subroutine builder
      # @param patterns [Array<Pattern>] patterns to convert to subroutines
      # @param type [Symbol] subroutine type (:local or :global)
      def initialize(patterns, type: :local)
        @patterns = patterns
        @type = type
        @subroutines = []
      end

      # Build subroutines from patterns
      # Each subroutine consists of the pattern bytes followed by a return
      # operator. The order matches the pattern array order.
      #
      # @return [Array<String>] subroutine CharStrings
      def build
        @subroutines = @patterns.map do |pattern|
          build_subroutine_charstring(pattern)
        end
        @subroutines
      end

      # Calculate CFF bias for current subroutine count
      # Bias values defined by CFF specification:
      # - 107 for count < 1240
      # - 1131 for count < 33900
      # - 32768 for count >= 33900
      #
      # @return [Integer] bias value
      def bias
        calculate_bias(@subroutines.length)
      end

      # Create callsubr operator for a subroutine
      # Encodes the biased subroutine ID as a CFF integer followed by the
      # callsubr operator.
      #
      # @param subroutine_id [Integer] zero-based subroutine index
      # @return [String] encoded callsubr operator
      def create_call(subroutine_id)
        biased_id = subroutine_id - bias
        encode_integer(biased_id) + CALLSUBR_OPERATOR
      end

      private

      # Build a subroutine CharString from a pattern
      # @param pattern [Pattern] pattern to convert
      # @return [String] subroutine CharString (pattern + return)
      def build_subroutine_charstring(pattern)
        pattern.bytes + RETURN_OPERATOR
      end

      # Calculate bias based on subroutine count
      # @param count [Integer] number of subroutines
      # @return [Integer] bias value
      def calculate_bias(count)
        return 107 if count < 1240
        return 1131 if count < 33_900

        32_768
      end

      # Encode an integer using CFF integer encoding
      # CFF spec defines multiple encoding formats based on value range:
      # - -107..107: single byte (32 + n)
      # - 108..1131: two bytes (247 prefix)
      # - -1131..-108: two bytes (251 prefix)
      # - -32768..32767: three bytes (29 prefix)
      # - Otherwise: five bytes (255 prefix)
      #
      # @param num [Integer] integer to encode
      # @return [String] encoded bytes
      def encode_integer(num)
        # Range 1: -107 to 107 (single byte)
        # CFF spec: byte value = 139 + number
        if num >= -107 && num <= 107
          return [139 + num].pack("C")
        end

        # Range 2: 108 to 1131 (two bytes)
        if num >= 108 && num <= 1131
          b0 = 247 + ((num - 108) >> 8)
          b1 = (num - 108) & 0xff
          return [b0, b1].pack("C*")
        end

        # Range 3: -1131 to -108 (two bytes)
        if num >= -1131 && num <= -108
          b0 = 251 - ((num + 108) >> 8)
          b1 = -(num + 108) & 0xff
          return [b0, b1].pack("C*")
        end

        # Range 4: -32768 to 32767 (three bytes)
        if num >= -32_768 && num <= 32_767
          b0 = 29
          b1 = (num >> 8) & 0xff
          b2 = num & 0xff
          return [b0, b1, b2].pack("C*")
        end

        # Range 5: Larger numbers (five bytes)
        b0 = 255
        b1 = (num >> 24) & 0xff
        b2 = (num >> 16) & 0xff
        b3 = (num >> 8) & 0xff
        b4 = num & 0xff
        [b0, b1, b2, b3, b4].pack("C*")
      end
    end
  end
end
