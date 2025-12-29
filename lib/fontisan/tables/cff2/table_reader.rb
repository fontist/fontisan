# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff2
      # Table reader for CFF2 with Variable Store support
      #
      # CFF2TableReader parses CFF2 tables and extracts variation data
      # from the Variable Store, which is essential for applying hints
      # to variable fonts with CFF2 outlines.
      #
      # Variable Store Structure:
      # - RegionList: Defines variation regions (min/peak/max per axis)
      # - ItemVariationData: Contains delta arrays per region
      #
      # Reference: Adobe Technical Note #5177 (CFF2)
      # Reference: OpenType spec - Item Variation Store
      #
      # @example Reading CFF2 with Variable Store
      #   reader = CFF2TableReader.new(cff2_data)
      #   store = reader.read_variable_store
      #   regions = store[:regions]
      #   deltas = store[:deltas]
      class TableReader
        # @return [String] Binary CFF2 data
        attr_reader :data

        # @return [Hash] CFF2 header information
        attr_reader :header

        # @return [Hash] Top DICT data
        attr_reader :top_dict

        # @return [Hash, nil] Variable Store data
        attr_reader :variable_store

        # CFF2-specific operators
        VSTORE_OPERATOR = 24

        # Initialize reader with CFF2 data
        #
        # @param data [String] Binary CFF2 table data
        def initialize(data)
          @data = data
          @io = StringIO.new(data)
          @io.set_encoding(Encoding::BINARY)
          @header = nil
          @top_dict = nil
          @variable_store = nil
        end

        # Read CFF2 header
        #
        # @return [Hash] Header information
        def read_header
          @io.rewind
          @header = {
            major_version: read_uint8,
            minor_version: read_uint8,
            header_size: read_uint8,
            top_dict_length: read_uint16,
          }

          # Validate CFF2 version
          unless @header[:major_version] == 2 && @header[:minor_version].zero?
            raise CorruptedTableError,
                  "Invalid CFF2 version: #{@header[:major_version]}.#{@header[:minor_version]}"
          end

          @header
        end

        # Read Top DICT
        #
        # @return [Hash] Top DICT operators and values
        def read_top_dict
          read_header unless @header

          # Seek to Top DICT (after header)
          @io.seek(@header[:header_size])

          top_dict_data = @io.read(@header[:top_dict_length])
          @top_dict = parse_dict(top_dict_data)
        end

        # Read Variable Store from Top DICT
        #
        # The Variable Store is referenced by the vstore operator (24)
        # in the Top DICT. It contains regions and deltas for variation.
        #
        # @return [Hash, nil] Variable Store data with :regions and :deltas
        def read_variable_store
          read_top_dict unless @top_dict

          # Check if Variable Store is present (operator 24)
          vstore_offset = @top_dict[VSTORE_OPERATOR]
          return nil unless vstore_offset

          # Seek to Variable Store
          @io.seek(vstore_offset)

          # Parse Variable Store structure
          @variable_store = {
            regions: read_region_list,
            item_variation_data: read_item_variation_data,
          }

          @variable_store
        end

        # Read Region List from Variable Store
        #
        # Region List defines variation regions, where each region
        # specifies min/peak/max values per axis.
        #
        # @return [Array<Hash>] Array of region definitions
        def read_region_list
          region_count = read_uint16
          regions = []

          region_count.times do
            region = read_region
            regions << region
          end

          regions
        end

        # Read a single region
        #
        # @return [Hash] Region with axis coordinates
        def read_region
          axis_count = read_uint16
          axes = []

          axis_count.times do
            axes << {
              start_coord: read_f2dot14,
              peak_coord: read_f2dot14,
              end_coord: read_f2dot14,
            }
          end

          { axis_count: axis_count, axes: axes }
        end

        # Read Item Variation Data
        #
        # Contains delta arrays per region for varying values
        #
        # @return [Array<Hash>] Array of item variation data
        def read_item_variation_data
          data_count = read_uint16
          return [] if data_count.zero?

          item_variation_data = []

          data_count.times do |_idx|
            item_data = read_single_item_variation_data
            item_variation_data << item_data
          rescue EOFError
            # break
          end

          item_variation_data
        end

        # Read a single Item Variation Data entry
        #
        # @return [Hash] Item variation data with region indices and deltas
        def read_single_item_variation_data
          item_count = read_uint16
          short_delta_count = read_uint16
          region_index_count = read_uint16

          # Read region indices
          region_indices = []
          region_index_count.times do
            region_indices << read_uint16
          end

          # Read delta sets
          delta_sets = []
          item_count.times do |_item_idx|
            deltas = []

            # Short deltas (16-bit)
            short_delta_count.times do
              break if @io.eof?

              deltas << read_int16
            end

            # Long deltas (8-bit) for remaining regions
            (region_index_count - short_delta_count).times do
              break if @io.eof?

              deltas << read_int8
            end

            delta_sets << deltas
          rescue EOFError
            # break
          end

          {
            item_count: item_count,
            region_indices: region_indices,
            delta_sets: delta_sets,
          }
        end

        # Read Private DICT with blend support
        #
        # Private DICT in CFF2 can contain blend operators for
        # variable hint parameters.
        #
        # @param size [Integer] Private DICT size
        # @param offset [Integer] Private DICT offset
        # @return [Hash] Private DICT data
        def read_private_dict(size, offset)
          @io.seek(offset)
          private_dict_data = @io.read(size)
          parse_dict(private_dict_data)
        end

        # Read CharStrings INDEX
        #
        # @param offset [Integer] CharStrings offset from Top DICT
        # @return [Cff::Index] CharStrings INDEX
        def read_charstrings(offset)
          @io.seek(offset)
          require_relative "../cff/index"
          Cff::Index.new(@io, start_offset: offset)
        end

        private

        # Read bytes safely with EOF checking
        #
        # @param bytes [Integer] Number of bytes to read
        # @param description [String] Description for error messages
        # @return [String] Binary data
        # @raise [EOFError] If not enough bytes available
        def read_safely(bytes, description)
          data = @io.read(bytes)
          if data.nil? || data.bytesize < bytes
            raise EOFError,
                  "Unexpected EOF while reading #{description}"
          end

          data
        end

        # Parse DICT structure
        #
        # @param data [String] DICT binary data
        # @return [Hash] Parsed operators and values
        def parse_dict(data)
          dict = {}
          io = StringIO.new(data)
          io.set_encoding(Encoding::BINARY)
          operands = []

          until io.eof?
            byte = io.getbyte

            if operator_byte?(byte)
              operator = read_dict_operator(io, byte)
              dict[operator] =
                operands.size == 1 ? operands.first : operands.dup
              operands.clear
            else
              # Operand (number)
              io.pos -= 1
              operands << read_dict_number(io)
            end
          end

          dict
        end

        # Check if byte is an operator
        #
        # CFF2 extends the operator range to include operator 24 (vstore)
        #
        # @param byte [Integer] Byte value
        # @return [Boolean] True if operator
        def operator_byte?(byte)
          # Standard DICT operators (0-21, excluding number markers)
          return true if byte <= 21 && ![12, 28, 29, 30, 31].include?(byte)

          # CFF2-specific operators
          return true if byte == VSTORE_OPERATOR

          false
        end

        # Read DICT operator
        #
        # @param io [StringIO] Input stream
        # @param first_byte [Integer] First operator byte
        # @return [Integer, Array<Integer>] Operator code
        def read_dict_operator(io, first_byte)
          if first_byte == 12
            # Two-byte operator
            second_byte = io.getbyte
            [12, second_byte]
          else
            first_byte
          end
        end

        # Read number from DICT
        #
        # @param io [StringIO] Input stream
        # @return [Integer, Float] Number value
        def read_dict_number(io)
          byte = io.getbyte

          case byte
          when 28
            # 3-byte signed integer
            b1 = io.getbyte
            b2 = io.getbyte
            value = (b1 << 8) | b2
            value > 0x7FFF ? value - 0x10000 : value
          when 29
            # 5-byte signed integer
            io.read(4).unpack1("l>")
          when 30
            # Real number
            read_real_number(io)
          when 32..246
            byte - 139
          when 247..250
            b2 = io.getbyte
            (byte - 247) * 256 + b2 + 108
          when 251..254
            b2 = io.getbyte
            -(byte - 251) * 256 - b2 - 108
          else
            0
          end
        end

        # Read real number from DICT
        #
        # @param io [StringIO] Input stream
        # @return [Float] Real number
        def read_real_number(io)
          nibbles = []
          loop do
            byte = io.getbyte
            nibbles << ((byte >> 4) & 0x0F)
            nibbles << (byte & 0x0F)
            break if (byte & 0x0F) == 0x0F
          end

          str = ""
          nibbles.each do |nibble|
            case nibble
            when 0..9 then str << nibble.to_s
            when 0x0A then str << "."
            when 0x0B then str << "E"
            when 0x0C then str << "E-"
            when 0x0E then str << "-"
            when 0x0F then break
            end
          end

          str.to_f
        end

        # Read unsigned 8-bit integer
        #
        # @return [Integer] Value
        def read_uint8
          read_safely(1, "uint8").unpack1("C")
        end

        # Read unsigned 16-bit integer (big-endian)
        #
        # @return [Integer] Value
        def read_uint16
          read_safely(2, "uint16").unpack1("n")
        end

        # Read signed 16-bit integer (big-endian)
        #
        # @return [Integer] Value
        def read_int16
          read_safely(2, "int16").unpack1("s>")
        end

        # Read signed 8-bit integer
        #
        # @return [Integer] Value
        def read_int8
          value = read_safely(1, "int8").unpack1("C")
          value > 0x7F ? value - 0x100 : value
        end

        # Read F2DOT14 format (signed 16-bit fixed-point)
        #
        # F2DOT14 represents a number in 2.14 format:
        # - 2 bits for integer part
        # - 14 bits for fractional part
        #
        # @return [Float] Value
        def read_f2dot14
          value = read_int16
          value / 16384.0
        end
      end
    end
  end
end
