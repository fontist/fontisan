# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Encodes CFF2 DICT data: sequences of (operands, operator) pairs.
      #
      # CFF2 DICTs use the same operand encoding as CFF1:
      #   32..246  → integer  (value = b0 - 139, range -107..107)
      #   247..250 → integer  (positive, 2 bytes, range 108..1131)
      #   251..254 → integer  (negative, 2 bytes, range -1131..-108)
      #   28       → integer  (3 bytes, range -32768..32767)
      #   29       → integer  (5 bytes, full int32)
      #   30       → real     (BCD nibble encoding)
      #
      # Operators are 1 byte (0..21) or 2 bytes (12, xx) for escapes.
      class DictEncoder
        # Encode a single integer operand.
        # @param value [Integer]
        # @return [String]
        def self.encode_integer(value)
          case value
          when -107..107
            [value + 139].pack("C")
          when 108..1131
            v = value - 108
            [(v >> 8) + 247, v & 0xFF].pack("CC")
          when -1131..-108
            v = -value - 108
            [(-(v >> 8)) + 251, -(v & 0xFF) & 0xFF].pack("CC")
          when -32768..32767
            [28, value].pack("Cn")
          else
            [29, value].pack("CN") # 29 + 4-byte signed int (big-endian)
          end
        end

        # Encode a real number operand using BCD nibble encoding.
        # @param value [Float]
        # @return [String]
        def self.encode_real(value)
          nibbles = real_to_nibbles(value)
          nibbles << 0x0F # end-of-number marker
          nibbles << 0x0F if nibbles.size.odd? # pad to even

          io = +""
          nibbles.each_slice(2) do |high, low|
            io << [(high << 4) | (low & 0x0F)].pack("C")
          end
          [30].pack("C") + io # prefix with operator byte 30
        end

        # Encode a DICT entry: operands followed by operator.
        # @param operands [Array<Integer, Float>]
        # @param operator [Integer, Array<Integer>] 1-byte or [12, xx] 2-byte
        # @return [String]
        def self.encode_entry(operands, operator)
          io = +""
          operands.each do |operand|
            io << (operand.is_a?(Float) ? encode_real(operand) : encode_integer(operand.to_i))
          end
          io << encode_operator(operator)
          io
        end

        # @param operator [Integer, Array<Integer>]
        # @return [String]
        def self.encode_operator(operator)
          operator.is_a?(Array) ? operator.pack("C*") : [operator].pack("C")
        end

        # Convert a float to BCD nibbles per the CFF spec.
        # @param value [Float]
        # @return [Array<Integer>]
        def self.real_to_nibbles(value)
          str = value.to_s
          nibbles = []
          str.each_char do |c|
            case c
            when "0".."9" then nibbles << c.to_i
            when "." then nibbles << 0x0A
            when "-" then nibbles << 0x0E
            when "e", "E"
              nibbles << 0x0B # positive exponent marker
            end
          end
          nibbles
        end

        private_class_method :real_to_nibbles
      end
    end
  end
end
