# frozen_string_literal: true

require "stringio"

module Fontisan
  module Woff2
    # 255UInt16 variable-length encoding per WOFF2 spec section 3.1.
    #
    # Single source of truth for encoding and decoding this data type. All
    # other WOFF2 code MUST delegate to this module — the previous inline
    # copies had the code-byte mapping inverted for values ≥ 253.
    #
    # Encoding table (per W3C spec pseudocode):
    #
    #   value range     | encoding              | bytes
    #   ----------------|-----------------------|------
    #   0 .. 252        | literal              | 1
    #   253 .. 505      | code 255 + (v - 253) | 2
    #   506 .. 761      | code 254 + (v - 506) | 2
    #   762 .. 65535    | code 253 + uint16    | 3
    #
    # Decoding (inverse):
    #
    #   code byte | meaning
    #   ----------|--------------------------------
    #   0 .. 252  | literal value
    #   253       | read uint16 → value
    #   254       | read 1 byte → value + 506
    #   255       | read 1 byte → value + 253
    module UInt255
      WORD_CODE = 253
      ONE_MORE_BYTE_CODE1 = 255 # adds 253
      ONE_MORE_BYTE_CODE2 = 254 # adds 506

      MAX_VALUE = 65_535

      # Encode a value (0..65535) into a 1-3 byte binary string.
      #
      # @param value [Integer]
      # @return [String] binary-encoded bytes
      # @raise [ArgumentError] if value is out of range
      def self.encode(value)
        case value
        when 0..252
          [value].pack("C")
        when 253..505
          [ONE_MORE_BYTE_CODE1, value - 253].pack("C*")
        when 506..761
          [ONE_MORE_BYTE_CODE2, value - 506].pack("C*")
        when 762..MAX_VALUE
          [WORD_CODE].pack("C") + [value].pack("n")
        else
          raise ArgumentError,
                "255UInt16 requires 0 <= value <= #{MAX_VALUE}, got #{value}"
        end
      end

      # Decode a 255UInt16 value from an IO stream. Reads 1-3 bytes.
      #
      # @param io [IO, StringIO] input stream positioned at the code byte
      # @return [Integer, nil] decoded value, or nil if the stream is empty
      def self.decode(io)
        code = io.read(1)&.unpack1("C")
        return nil unless code

        case code
        when 0..252
          code
        when WORD_CODE
          io.read(2)&.unpack1("n")
        when ONE_MORE_BYTE_CODE2
          506 + (io.read(1)&.unpack1("C") || 0)
        when ONE_MORE_BYTE_CODE1
          253 + (io.read(1)&.unpack1("C") || 0)
        end
      end

      # Decode from a binary String at a given position. Returns the value
      # and the new cursor position. Used by callers that index into a
      # flat String rather than wrapping it in a StringIO.
      #
      # @param data [String] binary data
      # @param pos [Integer] byte offset of the code byte
      # @return [Array(Integer, Integer)] [value, new_pos]
      def self.decode_at(data, pos)
        code = data.getbyte(pos)
        pos += 1
        case code
        when 0..252
          [code, pos]
        when WORD_CODE
          [data[pos, 2].unpack1("n"), pos + 2]
        when ONE_MORE_BYTE_CODE2
          [506 + data.getbyte(pos), pos + 1]
        when ONE_MORE_BYTE_CODE1
          [253 + data.getbyte(pos), pos + 1]
        end
      end
    end
  end
end
