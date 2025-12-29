# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Parser for the 'CFF2' (Compact Font Format 2) table
    #
    # CFF2 is used primarily in variable fonts with PostScript outlines.
    # Key differences from CFF:
    # - No Name INDEX (font names come from name table)
    # - No Encoding or Charset (use cmap table instead)
    # - Support for blend operators in CharStrings for variations
    # - Different default values in DICTs
    #
    # Reference: Adobe Technical Note #5177
    #
    # @example Reading a CFF2 table
    #   data = font.table_data("CFF2")
    #   cff2 = Fontisan::Tables::Cff2.read(data)
    #   num_glyphs = cff2.glyph_count
    class Cff2 < Binary::BaseRecord
      # CFF2 header structure
      class Cff2Header < Binary::BaseRecord
        uint8 :major_version
        uint8 :minor_version
        uint8 :header_size
        uint16 :top_dict_length

        # Check if version is valid
        #
        # @return [Boolean] True if version is 2.0
        def valid?
          major_version == 2 && minor_version.zero?
        end
      end

      # Parse the CFF2 table
      #
      # @return [self]
      def parse
        return self if @parsed

        @header = parse_header
        @global_subr_index = parse_global_subr_index
        @top_dict = parse_top_dict
        @charstrings_index = parse_charstrings_index

        @parsed = true
        self
      end

      # Get the CFF2 header
      #
      # @return [Cff2Header] Header structure
      def header
        parse unless @parsed
        @header
      end

      # Get glyph count from font's maxp table
      #
      # CFF2 doesn't store glyph count internally - it relies on the maxp table
      #
      # @return [Integer] Number of glyphs (requires access to font's maxp)
      def glyph_count
        # This needs to be set externally or retrieved from maxp table
        # For now, return a default that indicates it needs to be set
        @glyph_count || 0
      end

      # Set glyph count (from maxp table)
      #
      # @param count [Integer] Number of glyphs
      def glyph_count=(count)
        @glyph_count = count
      end

      # Set number of variation axes (from fvar table)
      #
      # @param count [Integer] Number of axes
      def num_axes=(count)
        @num_axes = count
      end

      # Get number of variation axes
      #
      # @return [Integer] Number of axes
      def num_axes
        @num_axes || 0
      end

      # Get CharString for a specific glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [CharstringParser, nil] CharString object or nil
      def charstring_for_glyph(glyph_id)
        parse unless @parsed
        return nil if @charstrings_index.nil?
        return nil if glyph_id >= @charstrings_index.count

        # Get CharString data from INDEX
        charstring_data = @charstrings_index[glyph_id]
        return nil if charstring_data.nil?

        # Parse with CFF2 CharString parser
        require_relative "cff2/charstring_parser"
        CharstringParser.new(
          charstring_data,
          @num_axes,
          @global_subr_index,
          nil, # local subrs (CFF2 may not have them)
          0, # vsindex
        ).parse
      end

      # Get all CharStrings
      #
      # @return [Array<CharstringParser>] Array of parsed CharStrings
      def charstrings
        return [] unless @charstrings_index

        @charstrings_index.count.times.map do |glyph_id|
          charstring_for_glyph(glyph_id)
        end.compact
      end

      # Check if table is valid
      #
      # @return [Boolean] True if valid CFF2 table
      def valid?
        header.valid?
      end

      private

      # Parse CFF2 header
      #
      # @return [Cff2Header] Parsed header
      def parse_header
        data = raw_data
        return nil if data.nil? || data.bytesize < 5

        Cff2Header.read(data.byteslice(0, 5))
      end

      # Parse Global Subr INDEX
      #
      # @return [Cff::Index] Global subroutines INDEX
      def parse_global_subr_index
        # CFF2 has a Global Subr INDEX after the header
        data = raw_data
        return nil unless @header

        offset = @header.header_size

        # Global Subr INDEX follows header
        io = StringIO.new(data)
        io.seek(offset)

        require_relative "cff/index"
        Cff::Index.new(io, start_offset: offset)
      rescue StandardError => e
        warn "Failed to parse Global Subr INDEX: #{e.message}"
        nil
      end

      # Parse Top DICT
      #
      # @return [Hash] Top DICT data
      def parse_top_dict
        # CFF2 Top DICT follows the header (length specified in header)
        data = raw_data
        return {} unless @header

        offset = @header.header_size
        length = @header.top_dict_length

        return {} if offset + length > data.bytesize

        top_dict_data = data.byteslice(offset, length)

        # Parse Top DICT (simplified for now)
        # Full implementation would parse DICT operators
        parse_dict(top_dict_data)
      rescue StandardError => e
        warn "Failed to parse Top DICT: #{e.message}"
        {}
      end

      # Parse CharStrings INDEX
      #
      # @return [Cff::Index, nil] CharStrings INDEX
      def parse_charstrings_index
        # CharStrings INDEX location is specified in Top DICT
        # For now, we'll try to find it after Global Subr INDEX
        data = raw_data
        return nil unless @header

        # Calculate offset after header + global subr
        offset = @header.header_size

        # Skip Global Subr INDEX
        if @global_subr_index
          offset += calculate_index_size(@global_subr_index)
        end

        # Skip Top DICT
        offset += @header.top_dict_length

        io = StringIO.new(data)
        io.seek(offset)

        require_relative "cff/index"
        Cff::Index.new(io, start_offset: offset)
      rescue StandardError => e
        warn "Failed to parse CharStrings INDEX: #{e.message}"
        nil
      end

      # Parse a DICT structure
      #
      # @param data [String] DICT data
      # @return [Hash] Parsed operators and values
      def parse_dict(data)
        dict = {}
        io = StringIO.new(data)
        io.set_encoding(Encoding::BINARY)

        operands = []

        until io.eof?
          byte = io.getbyte

          if byte <= 21 && ![12, 28, 29, 30, 31].include?(byte)
            # Operator
            operator = byte
            if operator == 12
              operator = [12, io.getbyte]
            end

            dict[operator] = operands.dup
            operands.clear
          else
            # Operand (number)
            io.pos -= 1
            operands << read_dict_number(io)
          end
        end

        dict
      rescue StandardError
        {}
      end

      # Read a number from DICT data
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
          bytes = io.read(4)
          bytes.unpack1("l>")
        when 30
          # Real number (nibble-based)
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

      # Read a real number from DICT
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

        # Convert nibbles to string
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

      # Calculate size of an INDEX structure
      #
      # @param index [Cff::Index] INDEX structure
      # @return [Integer] Size in bytes
      def calculate_index_size(index)
        return 2 if index.count.zero? # Just count field

        # count (2) + offSize (1) + offsets + data
        count = index.count
        data_size = index.instance_variable_get(:@data_size) || 0
        off_size = index.instance_variable_get(:@off_size) || 4

        2 + 1 + ((count + 1) * off_size) + data_size
      end
    end
  end
end

# Load CFF2 subcomponents
require_relative "cff2/charstring_parser"
require_relative "cff2/blend_operator"
require_relative "cff2/operand_stack"
require_relative "cff2/table_reader"
require_relative "cff2/variation_data_extractor"
require_relative "cff2/region_matcher"
require_relative "cff2/private_dict_blend_handler"
require_relative "cff2/table_builder"
