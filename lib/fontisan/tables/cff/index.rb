# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # CFF INDEX structure
      #
      # INDEX is a fundamental data structure used throughout CFF for storing
      # arrays of variable-length data items. It's used for:
      # - Name INDEX (font names)
      # - String INDEX (string data)
      # - Global Subr INDEX (global subroutines)
      # - Local Subr INDEX (local subroutines)
      # - CharStrings INDEX (glyph programs)
      #
      # Structure:
      # - count (Card16): Number of objects stored in INDEX
      # - offSize (OffSize): Size of offset values (1-4 bytes)
      # - offset[count+1] (Offset): Array of offsets to data
      # - data: The actual data bytes
      #
      # Offsets are relative to the byte before the data array. The first
      # offset is always 1, not 0. The last offset points one byte past the
      # end of the data.
      #
      # Reference: CFF specification section 5 "INDEX Data"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Reading an INDEX
      #   index = Fontisan::Tables::Cff::Index.new(data)
      #   puts index.count  # => 3
      #   puts index[0]  # => first item data
      #   index.each { |item| puts item }
      class Index
        include Enumerable

        # @return [Integer] Number of items in the INDEX
        attr_reader :count

        # @return [Integer] Size of offset values (1-4 bytes)
        attr_reader :off_size

        # @return [Array<Integer>] Array of offsets (count + 1 elements)
        attr_reader :offsets

        # @return [String] Binary string containing all data
        attr_reader :data

        # Initialize an INDEX from binary data
        #
        # @param io [IO, StringIO, String] Binary data to parse
        # @param start_offset [Integer] Starting byte offset in the data
        def initialize(io, start_offset: 0)
          @io = io.is_a?(String) ? StringIO.new(io) : io
          @start_offset = start_offset
          @io.seek(start_offset) if @io.respond_to?(:seek)

          parse!
        end

        # Get the item at the specified index
        #
        # @param index [Integer] Zero-based index of item to retrieve
        # @return [String, nil] Binary data for the item, or nil if out of bounds
        def [](index)
          return nil if index.negative? || index >= count
          return "" if count.zero?

          # Offsets are 1-based in the data array
          start_pos = offsets[index] - 1
          end_pos = offsets[index + 1] - 1
          length = end_pos - start_pos

          data[start_pos, length]
        end

        # Iterate over each item in the INDEX
        #
        # @yield [String] Binary data for each item
        # @return [Enumerator] If no block given
        def each
          return enum_for(:each) unless block_given?

          count.times do |i|
            yield self[i]
          end
        end

        # Get all items as an array
        #
        # @return [Array<String>] Array of binary data strings
        def to_a
          Array.new(count) { |i| self[i] }
        end

        # Check if the INDEX is empty
        #
        # @return [Boolean] True if count is 0
        def empty?
          count.zero?
        end

        # Get the size of a specific item
        #
        # @param index [Integer] Zero-based index of item
        # @return [Integer, nil] Size in bytes, or nil if out of bounds
        def item_size(index)
          return nil if index.negative? || index >= count
          return 0 if count.zero?

          offsets[index + 1] - offsets[index]
        end

        # Calculate total size of the INDEX in bytes
        #
        # This includes the count, offSize, offset array, and data.
        #
        # @return [Integer] Total size in bytes
        def total_size
          return 2 if count.zero? # Just the count field

          # count (2) + offSize (1) + offset array + data
          2 + 1 + ((count + 1) * off_size) + data.bytesize
        end

        private

        # Parse the INDEX structure from the IO
        def parse!
          # Read count (Card16)
          @count = read_uint16

          # Empty INDEX has only count field
          if @count.zero?
            @off_size = 0
            @offsets = []
            @data = "".b
            return
          end

          # Read offSize (OffSize)
          @off_size = read_uint8

          # Validate offSize
          unless (1..4).cover?(@off_size)
            raise CorruptedTableError,
                  "Invalid INDEX offSize: #{@off_size} (must be 1-4)"
          end

          # Read offset array (count + 1 offsets)
          @offsets = Array.new(@count + 1) do
            read_offset(@off_size)
          end

          # Validate offsets
          validate_offsets!

          # Read data section
          # Size is (last offset - 1) since offsets are 1-based
          data_size = @offsets.last - 1
          @data = read_bytes(data_size)
        end

        # Read an unsigned 16-bit integer
        #
        # @return [Integer] The value
        def read_uint16
          bytes = read_bytes(2)
          bytes.unpack1("n") # Big-endian unsigned 16-bit
        end

        # Read an unsigned 8-bit integer
        #
        # @return [Integer] The value
        def read_uint8
          read_bytes(1).unpack1("C")
        end

        # Read an offset value of specified size
        #
        # @param size [Integer] Number of bytes (1-4)
        # @return [Integer] The offset value
        def read_offset(size)
          bytes = read_bytes(size)

          case size
          when 1
            bytes.unpack1("C")
          when 2
            bytes.unpack1("n")
          when 3
            # 24-bit big-endian
            bytes.unpack("C3").inject(0) { |sum, byte| (sum << 8) | byte }
          when 4
            bytes.unpack1("N")
          else
            raise ArgumentError, "Invalid offset size: #{size}"
          end
        end

        # Read specified number of bytes from IO
        #
        # @param count [Integer] Number of bytes to read
        # @return [String] Binary string
        def read_bytes(count)
          return "".b if count.zero?

          bytes = @io.read(count)
          if bytes.nil? || bytes.bytesize < count
            raise CorruptedTableError,
                  "Unexpected end of INDEX data"
          end

          bytes
        end

        # Validate that offsets are in ascending order and within bounds
        def validate_offsets!
          # First offset must be 1
          unless @offsets.first == 1
            raise CorruptedTableError,
                  "Invalid INDEX: first offset must be 1, got #{@offsets.first}"
          end

          # Check ascending order
          @offsets.each_cons(2) do |prev, curr|
            if curr < prev
              raise CorruptedTableError,
                    "Invalid INDEX: offsets are not in ascending order"
            end
          end
        end
      end
    end
  end
end
