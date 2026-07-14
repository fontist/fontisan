# frozen_string_literal: true

module Fontisan
  module Utilities
    # Stateless helpers for SFNT byte-alignment padding.
    #
    # OpenType and WOFF/WOFF2 require table data and certain directory
    # blocks to be aligned to 4-byte boundaries with trailing null
    # bytes. The same `(N - (size % N)) % N` arithmetic was duplicated
    # across nine call sites before extraction; this module is the
    # single source of truth.
    #
    # All public methods take an Integer size. Callers with a String
    # compute `.bytesize` first.
    #
    # @example Get padding length
    #   Padding.boundary(13)              # => 3
    #   Padding.boundary(13, boundary: 4) # => 3
    #   Padding.boundary(16, boundary: 4) # => 0
    #
    # @example Get padded bytes
    #   Padding.pad("abc")               # => "abc\x00"
    #   Padding.pad("abcd")              # => "abcd"
    module Padding
      # Count of trailing pad bytes needed to align `size` to `boundary`.
      #
      # @param size [Integer] Size in bytes (callers with a String
      #   compute `.bytesize` first).
      # @param boundary [Integer] Alignment boundary in bytes (default
      #   `Constants::TABLE_ALIGNMENT`).
      # @return [Integer] Number of pad bytes in 0...boundary-1
      def self.boundary(size, boundary: Constants::TABLE_ALIGNMENT)
        (boundary - (size % boundary)) % boundary
      end

      # Return `bytes` followed by null padding to the requested boundary.
      #
      # @param bytes [String] Binary string to pad.
      # @param boundary [Integer] Alignment boundary in bytes.
      # @return [String] The original string if already aligned, else a
      #   new binary string with trailing nulls.
      def self.pad(bytes, boundary: Constants::TABLE_ALIGNMENT)
        pad_count = boundary(bytes.bytesize, boundary:)
        return bytes if pad_count.zero?

        out = bytes.dup.force_encoding(Encoding::BINARY)
        out << ("\x00" * pad_count)
        out
      end

      # Aligned size of `size` after padding to `boundary`.
      #
      # @param size [Integer] Original size in bytes.
      # @param boundary [Integer] Alignment boundary in bytes.
      # @return [Integer] Size after alignment (multiple of `boundary`).
      def self.aligned_size(size, boundary: Constants::TABLE_ALIGNMENT)
        size + boundary(size, boundary:)
      end
    end
  end
end
