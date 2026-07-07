# frozen_string_literal: true

module Fontisan
  module Woff2
    # Computes head.checksumAdjustment for the SFNT that the WOFF2 decoder
    # reconstructs at runtime.
    #
    # Per OpenType spec, head.checksumAdjustment must be set so that the
    # uint32-wise sum of the entire SFNT file (offset table + table
    # directory + all tables) equals the magic 0xB1B0AFBA. Chrome's OTS
    # validates this; a stale value from the source font causes rejection
    # with "Failed to convert WOFF 2.0 font to SFNT" once any table has
    # been modified (head.flags bit 11, glyf/loca transformation, etc.).
    #
    # Reference: OpenType spec, "Calculating Checksums".
    class SfntChecksum
      # Per-table data the checksum is computed over. tag is the 4-byte
      # table tag, bytes is the (already reconstructed, post-transform)
      # table data the decoder will see.
      Table = Struct.new(:tag, :bytes, keyword_init: true)

      # @param flavor [Integer] sfnt version (0x00010000 for TrueType,
      #   0x4F54544F for CFF)
      # @param tables [Array<Table>] reconstructed tables in alphabetical
      #   tag order
      def initialize(flavor:, tables:)
        @flavor = flavor
        @tables = tables
      end

      # Compute the head.checksumAdjustment value (uint32).
      #
      # @return [Integer]
      def adjustment
        (Constants::CHECKSUM_ADJUSTMENT_MAGIC - total_checksum) & 0xFFFFFFFF
      end

      private

      # Whole-SFNT checksum with head.checksumAdjustment treated as 0.
      def total_checksum
        sum = offset_table_checksum
        sum = (sum + directory_checksum) & 0xFFFFFFFF
        @tables.each do |t|
          sum = (sum + per_table_checksum(t)) & 0xFFFFFFFF
        end
        sum
      end

      # Checksum of the 12-byte offset table (sfnt version + numTables +
      # searchRange + entrySelector + rangeShift).
      def offset_table_checksum
        n = @tables.size
        search_range = (2**Integer(Math.log2(n))) * 16
        entry_selector = Integer(Math.log2(n))
        range_shift = n * 16 - search_range
        bytes = [@flavor, n, search_range, entry_selector, range_shift]
          .pack("I>S>S>S>S>")
        uint32_sum(bytes.ljust(12, "\x00"))
      end

      # Checksum of the table directory (one 16-byte entry per table).
      # Each entry is tag(4) + checksum(4) + offset(4) + length(4).
      def directory_checksum
        offsets = {}
        cursor = 12 + @tables.size * 16
        @tables.each do |t|
          offsets[t.tag] = cursor
          cursor += padded_size(t.bytes.bytesize)
        end
        bytes = String.new(encoding: Encoding::BINARY)
        @tables.each do |t|
          tag_bytes = t.tag.encode(Encoding::BINARY).ljust(4, " ")
          bytes << tag_bytes
          bytes << [per_table_checksum(t)].pack("I>")
          bytes << [offsets[t.tag]].pack("I>")
          bytes << [t.bytes.bytesize].pack("I>")
        end
        uint32_sum(bytes)
      end

      # OpenType per-table checksum. The head table's checksumAdjustment
      # field (offset 8-11) is treated as zero per spec. Tables are
      # zero-padded to a 4-byte boundary for checksum, even when their
      # actual length is shorter.
      def per_table_checksum(table)
        bytes = table.bytes.dup.force_encoding(Encoding::BINARY)
        if table.tag == "head"
          bytes = "#{bytes.byteslice(0, 8)}\u0000\u0000\u0000\u0000#{bytes.byteslice(12..)}"
        end
        uint32_sum(pad_to_4(bytes))
      end

      def uint32_sum(bytes)
        bytes.unpack("I>*").sum & 0xFFFFFFFF
      end

      def pad_to_4(bytes)
        pad = (-bytes.bytesize) % 4
        pad.zero? ? bytes : bytes + ("\x00" * pad)
      end

      def padded_size(size)
        (size + 3) & ~3
      end
    end
  end
end
