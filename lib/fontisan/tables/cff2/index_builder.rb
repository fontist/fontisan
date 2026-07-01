# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # Builds CFF2 INDEX structures.
      #
      # A CFF2 INDEX is identical to a CFF1 INDEX except the count
      # field is uint32 (vs card16 in CFF1). This allows > 65,535
      # entries — though the CharStrings INDEX is still capped at
      # 65,535 by maxp.numGlyphs.
      #
      # Structure:
      #   count      (uint32)  number of objects
      #   offSize    (uint8)   1, 2, 3, or 4
      #   offsets    (offSize × (count + 1))  1-based, relative to
      #                                      the byte before data
      #   data       (variable)  concatenated object bytes
      #
      # An empty INDEX is just a 4-byte count field of 0.
      class IndexBuilder
        EMPTY_INDEX_BYTESIZE = 4

        # @param items [Array<String>] binary data items
        # @return [String] binary INDEX
        def self.build(items)
          return [0].pack("N") if items.empty?

          data = items.join.b
          off_size = off_size_for(data.bytesize + 1)
          offsets = build_offsets(items, off_size)

          io = +""
          io << [items.size].pack("N")     # count (uint32)
          io << [off_size].pack("C")       # offSize (uint8)
          io << offsets
          io << data
          io
        end

        # Smallest offSize that can represent the last offset.
        # @param max_offset [Integer] value of the last offset (data_size + 1)
        # @return [Integer] 1, 2, 3, or 4
        def self.off_size_for(max_offset)
          return 1 if max_offset <= 0xFF
          return 2 if max_offset <= 0xFFFF
          return 3 if max_offset <= 0xFFFFFF

          4
        end

        # Build the offset array. Offsets are 1-based and relative to
        # the byte preceding the data area. The first offset is always 1.
        def self.build_offsets(items, off_size)
          io = +""
          offset = 1
          io << pack_offset(offset, off_size)
          items.each do |item|
            offset += item.bytesize
            io << pack_offset(offset, off_size)
          end
          io
        end

        def self.pack_offset(value, off_size)
          case off_size
          when 1 then [value].pack("C")
          when 2 then [value].pack("n")
          when 3 then [value].pack("C3")
          when 4 then [value].pack("N")
          else raise ArgumentError, "invalid off_size: #{off_size}"
          end
        end

        private_class_method :off_size_for, :build_offsets, :pack_offset
      end
    end
  end
end
