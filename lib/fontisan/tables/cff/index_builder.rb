# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    class Cff
      # CFF INDEX structure builder
      #
      # [`IndexBuilder`](lib/fontisan/tables/cff/index_builder.rb) constructs
      # binary INDEX structures from arrays of data items. INDEX is a fundamental
      # CFF data structure used for storing arrays of variable-length data.
      #
      # The builder calculates optimal offset sizes, constructs the offset array,
      # and produces compact binary output.
      #
      # Structure produced:
      # - count (Card16): Number of items
      # - offSize (OffSize): Size of offset values (1-4 bytes)
      # - offset[count+1] (Offset): Array of offsets to data
      # - data: Concatenated data bytes
      #
      # Offsets are 1-based (first offset is always 1). The last offset points
      # one byte past the end of the data.
      #
      # Reference: CFF specification section 5 "INDEX Data"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Building an INDEX
      #   items = ["data1".b, "data2".b, "data3".b]
      #   index_data = Fontisan::Tables::Cff::IndexBuilder.build(items)
      class IndexBuilder
        # Build INDEX structure from array of binary strings
        #
        # @param items [Array<String>] Array of binary data items
        # @return [String] Binary INDEX data
        # @raise [ArgumentError] If items is not an Array
        def self.build(items)
          validate_items!(items)

          return build_empty_index if items.empty?

          # Calculate total data size
          data_size = items.sum(&:bytesize)

          # Calculate optimal offset size (1-4 bytes)
          # Last offset will be data_size + 1 (1-based)
          off_size = calculate_off_size(data_size + 1)

          # Build offset array (count + 1 offsets)
          offsets = build_offsets(items, off_size)

          # Concatenate all data
          data = items.join

          # Assemble INDEX structure
          output = StringIO.new("".b)

          # Write count (Card16)
          output.write([items.length].pack("n"))

          # Write offSize (OffSize)
          output.putc(off_size)

          # Write offset array
          offsets.each do |offset|
            write_offset(output, offset, off_size)
          end

          # Write data
          output.write(data)

          output.string
        end

        # Build an empty INDEX (count = 0)
        #
        # @return [String] Binary empty INDEX
        def self.build_empty_index
          # Empty INDEX has only count field (0)
          [0].pack("n")
        end
        private_class_method :build_empty_index

        # Validate items parameter
        #
        # @param items [Object] Items to validate
        # @raise [ArgumentError] If items is invalid
        def self.validate_items!(items)
          raise ArgumentError, "items must be Array" unless items.is_a?(Array)

          items.each_with_index do |item, i|
            unless item.is_a?(String)
              raise ArgumentError,
                    "item #{i} must be String, got: #{item.class}"
            end
            unless item.encoding == ::Encoding::BINARY
              raise ArgumentError,
                    "item #{i} must have BINARY encoding, got: #{item.encoding}"
            end
          end
        end
        private_class_method :validate_items!

        # Calculate optimal offset size for given maximum offset
        #
        # @param max_offset [Integer] Maximum offset value
        # @return [Integer] Offset size (1-4 bytes)
        def self.calculate_off_size(max_offset)
          return 1 if max_offset <= 0xFF
          return 2 if max_offset <= 0xFFFF
          return 3 if max_offset <= 0xFFFFFF

          4
        end
        private_class_method :calculate_off_size

        # Build offset array from items
        #
        # Offsets are 1-based. First offset is always 1.
        # Each offset points to the start of its item in the data array.
        # Last offset points one byte past the end of data.
        #
        # @param items [Array<String>] Array of data items
        # @param off_size [Integer] Offset size (1-4 bytes)
        # @return [Array<Integer>] Array of offsets (count + 1 elements)
        def self.build_offsets(items, _off_size)
          offsets = []
          current_offset = 1 # 1-based

          # First offset is always 1
          offsets << current_offset

          # Calculate offset for each item
          items.each do |item|
            current_offset += item.bytesize
            offsets << current_offset
          end

          offsets
        end
        private_class_method :build_offsets

        # Write an offset value of specified size
        #
        # @param io [StringIO] Output stream
        # @param offset [Integer] Offset value to write
        # @param size [Integer] Number of bytes (1-4)
        def self.write_offset(io, offset, size)
          case size
          when 1
            io.putc(offset & 0xFF)
          when 2
            io.write([offset].pack("n")) # Big-endian unsigned 16-bit
          when 3
            # 24-bit big-endian
            io.putc((offset >> 16) & 0xFF)
            io.putc((offset >> 8) & 0xFF)
            io.putc(offset & 0xFF)
          when 4
            io.write([offset].pack("N")) # Big-endian unsigned 32-bit
          else
            raise ArgumentError, "Invalid offset size: #{size}"
          end
        end
        private_class_method :write_offset
      end
    end
  end
end
