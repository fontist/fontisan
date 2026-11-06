# frozen_string_literal: true

module Fontisan
  # Structural checks on a WOFF 1.0 container, run before the BinData parse.
  #
  # The native tiers decode a WOFF through fontisan-rs, which rejects a bad
  # container with InvalidFontError "woff: <reason>" (no cause). This applies the
  # same checks in the same order with the same messages, so every tier fails
  # the same way on the same input (fontist/fontisan#159) rather than leaking
  # whatever BinData or Zlib raise.
  module WoffContainer
    SIGNATURE = 0x774F4646 # 'wOFF'
    MAX_OUTPUT = 1 << 30
    PREFIX = "woff: "

    module_function

    # @param data [String] the whole file, binary
    # @raise [InvalidFontError] with a "woff: ..." message
    # @return [void]
    def check!(data)
      cur = Cursor.new(data)
      reject("not a WOFF file (bad signature)") unless cur.u32 == SIGNATURE
      cur.u32 # flavor
      reject("header length does not match file length") unless cur.u32 == data.bytesize
      num_tables = cur.u16
      reject("no tables") if num_tables.zero?
      cur.skip(2 + 4 + 4)
      meta_offset = cur.u32
      meta_length = cur.u32
      cur.skip(4)
      priv_offset = cur.u32
      priv_length = cur.u32
      [[meta_offset, meta_length], [priv_offset, priv_length]].each do |off, len|
        reject("metadata or private block out of range") if off != 0 && off + len > data.bytesize
      end
      check_directory!(cur, num_tables, data.bytesize)
    end

    def check_directory!(cur, num_tables, size)
      total = 12 + (16 * num_tables)
      tags = Array.new(num_tables) do
        tag, offset, comp, orig, = cur.u32, cur.u32, cur.u32, cur.u32, cur.u32
        reject("table compLength exceeds origLength") if comp > orig
        reject("table data out of range") if offset + comp > size
        total += (orig + 3) & ~3
        reject("decoded size too large") if total > MAX_OUTPUT
        tag
      end
      reject("table directory not sorted by unique tag") if tags.each_cons(2).any? { |a, b| a >= b }
    end

    def reject(message)
      raise InvalidFontError, "#{PREFIX}#{message}", cause: nil
    end

    # Bounds-checked big-endian reader.
    class Cursor
      def initialize(data)
        @data = data
        @pos = 0
      end

      def skip(count)
        take(count)
        nil
      end

      def u16 = take(2).unpack1("n")
      def u32 = take(4).unpack1("N")

      private

      def take(count)
        raise InvalidFontError.new("#{PREFIX}unexpected end of data"), cause: nil if count > @data.bytesize - @pos

        chunk = @data.byteslice(@pos, count)
        @pos += count
        chunk
      end
    end
  end
end
