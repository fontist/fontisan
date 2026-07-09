# frozen_string: true

module Fontisan
  module Woff2
    # Computes `head.checksumAdjustment` for the SFNT the WOFF2 decoder
    # reconstructs at runtime.
    #
    # Per OpenType spec ("Calculating Checksums"), checksumAdjustment
    # must be set so the uint32-wise sum of the entire SFNT file (offset
    # table + table directory + all tables) equals the magic
    # 0xB1B0AFBA. Chrome's OTS validates this; a stale value from the
    # source font causes rejection with "Failed to convert WOFF 2.0
    # font to SFNT" once any table has been modified (head.flags bit 11,
    # glyf/loca transformation, etc.).
    #
    # Delegates the per-table uint32 sum to {Utilities::ChecksumCalculator}
    # — that is the single source of truth for the OpenType checksum
    # algorithm. This class orchestrates the per-table layout: building
    # the offset table + table directory bytes, zeroing head's
    # checksumAdjustment field for its own checksum per spec, then
    # subtracting the total from the magic.
    class SfntChecksum
      # Per-table data the checksum is computed over.
      Table = Struct.new(:tag, :bytes, keyword_init: true)

      # @param flavor [Integer] sfnt version (0x00010000 for TrueType,
      #   0x4F54544F for CFF)
      # @param tables [Array<Table>] reconstructed tables in alphabetical
      # tag order
      def initialize(flavor:, tables:)
        @flavor = flavor
        @tables = tables
      end

      # Compute the head.checksumAdjustment value (uint32).
      #
      # @return [Integer]
      def adjustment
        Utilities::ChecksumCalculator.calculate_adjustment(total_checksum)
      end

      private

      # Whole-SFNT checksum with head.checksumAdjustment treated as 0
      # (per spec, head's own checksum field uses that placeholder).
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
        Utilities::ChecksumCalculator.calculate_table_checksum(offset_table_bytes)
      end

      def offset_table_bytes
        n = @tables.size
        search_range = (2**Integer(Math.log2(n))) * 16
        entry_selector = Integer(Math.log2(n))
        range_shift = n * 16 - search_range
        [@flavor, n, search_range, entry_selector, range_shift]
          .pack("I>S>S>S>S>")
          .ljust(12, "\x00")
      end

      # Checksum of the table directory (one 16-byte entry per table).
      # Each entry is tag(4) + checksum(4) + offset(4) + length(4).
      def directory_checksum
        Utilities::ChecksumCalculator.calculate_table_checksum(directory_bytes)
      end

      def directory_bytes
        cursor = offset_table_bytes.bytesize + @tables.size * 16
        offsets = {}
        @tables.each do |t|
          offsets[t.tag] = cursor
          cursor += Utilities::Padding.aligned_size(t.bytes)
        end

        bytes = String.new(encoding: Encoding::BINARY)
        @tables.each do |t|
          bytes << t.tag.encode(Encoding::BINARY).ljust(4, " ")
          bytes << [per_table_checksum(t)].pack("I>")
          bytes << [offsets[t.tag]].pack("I>")
          bytes << [t.bytes.bytesize].pack("I>")
        end
        bytes
      end

      # OpenType per-table checksum. The head table's checksumAdjustment
      # field (offset 8-11) is treated as zero per spec.
      def per_table_checksum(table)
        data = table.bytes
        if table.tag == "head"
          data = "#{data.byteslice(0,
                                   8)}#{['00000000'].pack('H8')}#{data.byteslice(12..)}"
        end
        Utilities::ChecksumCalculator.calculate_table_checksum(data)
      end
    end
  end
end
