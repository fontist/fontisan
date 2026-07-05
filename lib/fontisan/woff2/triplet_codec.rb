# frozen_string_literal: true

module Fontisan
  module Woff2
    # Variable-length coordinate codec for the WOFF2 glyf transform.
    #
    # Per WOFF2 spec section 5.2, each (dx, dy, on_curve) point is encoded as
    # one flag byte plus 1-4 payload bytes ("triplets"). The flag byte's high
    # bit is the on-curve flag; the low 7 bits select one of 128 encoding
    # variants. Variants are chosen by coordinate magnitude so small deltas
    # cost 1-2 bytes and only very large deltas cost 4.
    #
    # Reference: WOFF2 spec section 5.2 (triplet encoding table).
    module TripletCodec
      ON_CURVE_BIT = 0x00
      OFF_CURVE_BIT = 0x80

      # Encode a single (dx, dy) delta with the given on-curve flag.
      #
      # @param dx [Integer] X delta (signed, -65535..65535)
      # @param dy [Integer] Y delta (signed, -65535..65535)
      # @param on_curve [Boolean] true if this is an on-curve point
      # @return [Array(Integer, Array<Integer>)] flag byte and payload bytes
      def self.encode(dx, dy, on_curve:)
        on_curve_bit = on_curve ? ON_CURVE_BIT : OFF_CURVE_BIT
        abs_x = dx.abs
        abs_y = dy.abs
        x_sign_bit = dx.negative? ? 0 : 1
        y_sign_bit = dy.negative? ? 0 : 1
        xy_sign_bits = x_sign_bit + (2 * y_sign_bit)

        if dx.zero? && abs_y < 1280
          encode_y_only(on_curve_bit, abs_y, y_sign_bit)
        elsif dy.zero? && abs_x < 1280
          encode_x_only(on_curve_bit, abs_x, x_sign_bit)
        elsif abs_x < 65 && abs_y < 65
          encode_nibble_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
        elsif abs_x < 769 && abs_y < 769
          encode_byte_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
        elsif abs_x < 4096 && abs_y < 4096
          encode_12_bit_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
        else
          encode_16_bit_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
        end
      end

      # Decode one triplet given the flag byte and a cursor over payload bytes.
      #
      # @param flag [Integer] flag byte
      # @param payload [Array<Integer>] payload bytes following the flag
      # @return [Array(Integer, Integer, Boolean)] dx, dy, on_curve
      def self.decode(flag, payload)
        on_curve = (flag & OFF_CURVE_BIT).zero?
        idx = flag & 0x7F

        dx, dy = if idx < 10
                   decode_y_only(idx, payload)
                 elsif idx < 20
                   decode_x_only(idx, payload)
                 elsif idx < 84
                   decode_nibble_pair(idx, payload)
                 elsif idx < 120
                   decode_byte_pair(idx, payload)
                 elsif idx < 124
                   decode_12_bit_pair(idx, payload)
                 else
                   decode_16_bit_pair(idx, payload)
                 end
        [dx, dy, on_curve]
      end

      class << self
        private

        # --- Encoders ---

        # Variants 0-9: dy only (1 byte payload), dx=0, |dy| < 1280.
        def encode_y_only(on_curve_bit, abs_y, y_sign_bit)
          flag = on_curve_bit + ((abs_y & 0xF00) >> 7) + y_sign_bit
          [flag, [abs_y & 0xFF]]
        end

        # Variants 10-19: dx only (1 byte payload), dy=0, |dx| < 1280.
        def encode_x_only(on_curve_bit, abs_x, x_sign_bit)
          flag = on_curve_bit + 10 + ((abs_x & 0xF00) >> 7) + x_sign_bit
          [flag, [abs_x & 0xFF]]
        end

        # Variants 20-83: 4-bit X + 4-bit Y deltas (1 byte payload).
        # Encodes (abs - 1) so the range 1..64 maps to nibble values 0..63.
        def encode_nibble_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
          flag = on_curve_bit + 20 +
            ((abs_x - 1) & 0x30) +
            (((abs_y - 1) & 0x30) >> 2) +
            xy_sign_bits
          payload = (((abs_x - 1) & 0x0F) << 4) | ((abs_y - 1) & 0x0F)
          [flag, [payload]]
        end

        # Variants 84-119: 8-bit X + 8-bit Y deltas (2 byte payload).
        # Encodes (abs - 1) so the range 1..768 maps to byte values 0..767.
        def encode_byte_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
          flag = on_curve_bit + 84 +
            (12 * (((abs_x - 1) & 0x300) >> 8)) +
            (((abs_y - 1) & 0x300) >> 6) +
            xy_sign_bits
          [flag, [(abs_x - 1) & 0xFF, (abs_y - 1) & 0xFF]]
        end

        # Variants 120-123: 12-bit X + 12-bit Y deltas (3 byte payload).
        def encode_12_bit_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
          flag = on_curve_bit + 120 + xy_sign_bits
          payload = [
            (abs_x >> 4) & 0xFF,
            ((abs_x & 0x0F) << 4) | ((abs_y >> 8) & 0x0F),
            abs_y & 0xFF,
          ]
          [flag, payload]
        end

        # Variants 124-127: 16-bit X + 16-bit Y deltas (4 byte payload).
        def encode_16_bit_pair(on_curve_bit, abs_x, abs_y, xy_sign_bits)
          flag = on_curve_bit + 124 + xy_sign_bits
          payload = [
            (abs_x >> 8) & 0xFF, abs_x & 0xFF,
            (abs_y >> 8) & 0xFF, abs_y & 0xFF
          ]
          [flag, payload]
        end

        # --- Decoders ---

        def decode_y_only(idx, payload)
          sign = (idx & 1).zero? ? -1 : 1
          magnitude = ((idx & 0x0E) << 7) + payload.fetch(0)
          [0, sign * magnitude]
        end

        def decode_x_only(idx, payload)
          sign = (idx & 1).zero? ? -1 : 1
          magnitude = (((idx - 10) & 0x0E) << 7) + payload.fetch(0)
          [sign * magnitude, 0]
        end

        def decode_nibble_pair(idx, payload)
          x_sign = ((idx - 20) & 0x01).zero? ? -1 : 1
          y_sign = ((idx - 20) & 0x02).zero? ? -1 : 1
          x_mag_base = ((idx - 20) & 0x30) +
            ((payload.fetch(0) >> 4) & 0x0F) + 1
          y_mag_base = (((idx - 20) & 0x0C) << 2) +
            (payload.fetch(0) & 0x0F) + 1
          [x_sign * x_mag_base, y_sign * y_mag_base]
        end

        def decode_byte_pair(idx, payload)
          x_sign = (idx & 1).zero? ? -1 : 1
          y_sign = ((idx >> 1) & 1).zero? ? -1 : 1
          x_mag = 1 + (((idx - 84) / 12) << 8) + payload.fetch(0)
          y_mag = 1 + ((((idx - 84) % 12) >> 2) << 8) + payload.fetch(1)
          [x_sign * x_mag, y_sign * y_mag]
        end

        def decode_12_bit_pair(idx, payload)
          x_sign = (idx & 1).zero? ? -1 : 1
          y_sign = ((idx >> 1) & 1).zero? ? -1 : 1
          x_mag = (payload.fetch(0) << 4) + (payload.fetch(1) >> 4)
          y_mag = ((payload.fetch(1) & 0x0F) << 8) + payload.fetch(2)
          [x_sign * x_mag, y_sign * y_mag]
        end

        def decode_16_bit_pair(idx, payload)
          x_sign = (idx & 1).zero? ? -1 : 1
          y_sign = ((idx >> 1) & 1).zero? ? -1 : 1
          x_mag = (payload.fetch(0) << 8) + payload.fetch(1)
          y_mag = (payload.fetch(2) << 8) + payload.fetch(3)
          [x_sign * x_mag, y_sign * y_mag]
        end
      end
    end
  end
end
