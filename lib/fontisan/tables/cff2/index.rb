# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff2
      # Reads a CFF2 INDEX structure.
      #
      # A CFF2 INDEX uses a 4-byte count (Card32) instead of the
      # 2-byte count (Card16) used by CFF1. Otherwise the layout is
      # the same: count, offSize, offset array (1-based), then data.
      #
      # An empty INDEX is just the 4-byte count field (= 0).
      #
      # @example
      #   idx = Cff2::Index.read(raw_cff2_bytes, charstrings_offset)
      #   idx[0]  # first item
      #   idx.count
      #   idx.total_size
      class Index
        include Enumerable

        attr_reader :count, :off_size, :offsets, :data, :start_offset

        # Read a CFF2 INDEX at +offset+ within +raw_data+.
        #
        # @param raw_data [String] full CFF2 table bytes
        # @param offset [Integer] byte offset of the INDEX
        def self.read(raw_data, offset)
          io = StringIO.new(raw_data)
          io.seek(offset)
          new(io, offset)
        end

        # Build an INDEX from a list of data items.
        # Delegates to {IndexBuilder}.
        #
        # @param items [Array<String>]
        # @return [String] binary INDEX bytes
        def self.build(items)
          IndexBuilder.build(items)
        end

        # @param io [IO, StringIO] positioned at the INDEX start
        # @param start_offset [Integer] byte offset (for diagnostics)
        def initialize(io, start_offset = 0)
          @io = io
          @start_offset = start_offset
          parse!
        end

        # Fetch the item at +index+ (0-based).
        #
        # @return [String, nil] binary data, or nil if out of range
        def [](index)
          return nil if index.negative? || index >= count
          return "".b if count.zero?

          start_pos = offsets[index] - 1
          end_pos = offsets[index + 1] - 1
          data[start_pos, end_pos - start_pos]
        end

        # Iterate over all items.
        def each
          return enum_for(:each) unless block_given?

          count.times { |i| yield self[i] }
        end

        # All items as an array.
        def to_a
          Array.new(count) { |i| self[i] }
        end

        def empty?
          count.zero?
        end

        # Total size of the INDEX in bytes (count + offSize + offsets + data).
        def total_size
          return 4 if count.zero?

          4 + 1 + ((count + 1) * off_size) + data.bytesize
        end

        private

        def parse!
          @count = read_uint32

          if @count.zero?
            @off_size = 0
            @offsets = []
            @data = "".b
            return
          end

          @off_size = read_uint8
          raise CorruptedTableError, "invalid CFF2 offSize: #{@off_size}" unless (1..4).cover?(@off_size)

          @offsets = Array.new(@count + 1) { read_offset(@off_size) }
          validate_offsets!

          data_size = @offsets.last - 1
          @data = read_bytes(data_size)
        end

        def read_uint32
          read_bytes(4).unpack1("N")
        end

        def read_uint8
          read_bytes(1).unpack1("C")
        end

        def read_offset(size)
          bytes = read_bytes(size)
          case size
          when 1 then bytes.unpack1("C")
          when 2 then bytes.unpack1("n")
          when 3 then bytes.unpack("C3").inject(0) { |s, b| (s << 8) | b }
          when 4 then bytes.unpack1("N")
          end
        end

        def read_bytes(n)
          return "".b if n.zero?

          bytes = @io.read(n)
          if bytes.nil? || bytes.bytesize < n
            raise CorruptedTableError,
                  "unexpected EOF in CFF2 INDEX at offset #{@start_offset}"
          end

          bytes
        end

        def validate_offsets!
          unless @offsets.first == 1
            raise CorruptedTableError,
                  "CFF2 INDEX first offset must be 1, got #{@offsets.first}"
          end

          @offsets.each_cons(2) do |prev, curr|
            next unless curr < prev

            raise CorruptedTableError, "CFF2 INDEX offsets not ascending"
          end
        end
      end
    end
  end
end
