# frozen_string_literal: true

require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Parser for the 'loca' (Index to Location) table
    #
    # The loca table provides offsets to glyph data in the glyf table.
    # Each glyph has an entry in this table indicating where its data
    # begins in the glyf table. An additional entry marks the end of the
    # last glyph's data.
    #
    # The table has two formats:
    # - Short format (0): uint16 offsets divided by 2 (actual offset = value × 2)
    # - Long format (1): uint32 offsets used as-is
    #
    # The format is determined by head.indexToLocFormat:
    # - 0 = short format (uint16, multiply by 2)
    # - 1 = long format (uint32, use as-is)
    #
    # The table always contains (numGlyphs + 1) offsets, where the last
    # offset marks the end of the last glyph's data in the glyf table.
    #
    # The table is context-dependent and requires:
    # - indexToLocFormat from head table (format selection)
    # - numGlyphs from maxp table (number of offsets to read)
    #
    # Reference: OpenType specification, loca table
    # https://docs.microsoft.com/en-us/typography/opentype/spec/loca
    #
    # @example Parsing loca with context
    #   # Get required tables first
    #   head = font.table('head')
    #   maxp = font.table('maxp')
    #
    #   # Parse loca with context
    #   data = font.read_table_data('loca')
    #   loca = Fontisan::Tables::Loca.read(data)
    #   loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
    #
    #   # Get offset for a glyph
    #   offset = loca.offset_for(42)
    #   size = loca.size_of(42)
    #   is_empty = loca.empty?(42)
    class Loca < Binary::BaseRecord
      # Short format constant (from head.indexToLocFormat)
      FORMAT_SHORT = 0

      # Long format constant (from head.indexToLocFormat)
      FORMAT_LONG = 1

      # Store the raw data for deferred parsing
      attr_accessor :raw_data

      # Parsed offsets array
      # @return [Array<Integer>] Array of glyph offsets in glyf table
      attr_reader :offsets

      # Format of the loca table (0 = short, 1 = long)
      # @return [Integer] Format indicator
      attr_reader :format

      # Total number of glyphs from maxp table
      # @return [Integer] Total glyph count
      attr_reader :num_glyphs

      # Override read to capture raw data
      #
      # @param io [IO, String] Input data
      # @return [Loca] Parsed table instance
      def self.read(io)
        instance = new

        # Handle nil or empty data gracefully
        instance.raw_data = if io.nil?
                              "".b
                            elsif io.is_a?(String)
                              io
                            else
                              io.read || "".b
                            end

        instance
      end

      # Parse the table with font context
      #
      # This method must be called after reading the table data, providing
      # the indexToLocFormat from head and numGlyphs from maxp.
      #
      # @param index_to_loc_format [Integer] Format (0 = short, 1 = long) from head table
      # @param num_glyphs [Integer] Total number of glyphs from maxp table
      # @raise [ArgumentError] If context parameters are invalid
      # @raise [Fontisan::CorruptedTableError] If table data is insufficient
      def parse_with_context(index_to_loc_format, num_glyphs)
        validate_context_params(index_to_loc_format, num_glyphs)

        @format = index_to_loc_format
        @num_glyphs = num_glyphs

        io = StringIO.new(raw_data)
        io.set_encoding(Encoding::BINARY)

        # Number of offsets is numGlyphs + 1 (extra offset marks end of last glyph)
        offset_count = num_glyphs + 1

        @offsets = if short_format?
                     parse_short_offsets(io, offset_count)
                   else
                     parse_long_offsets(io, offset_count)
                   end

        validate_parsed_data!(io, offset_count)
      end

      # Get the offset for a specific glyph ID in the glyf table
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Integer, nil] Byte offset in glyf table, or nil if invalid ID
      # @raise [RuntimeError] If table has not been parsed with context
      #
      # @example Getting glyph offset
      #   offset = loca.offset_for(0)  # .notdef glyph offset
      def offset_for(glyph_id)
        raise "Table not parsed. Call parse_with_context first." unless @offsets

        return nil if glyph_id >= num_glyphs || glyph_id.negative?

        offsets[glyph_id]
      end

      # Calculate the size of glyph data for a specific glyph ID
      #
      # The size is calculated as the difference between consecutive offsets:
      # size = offsets[glyph_id + 1] - offsets[glyph_id]
      #
      # A size of 0 indicates an empty glyph (no outline data).
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Integer, nil] Size in bytes, or nil if invalid ID
      # @raise [RuntimeError] If table has not been parsed with context
      #
      # @example Calculating glyph size
      #   size = loca.size_of(42)  # Size of glyph 42 in bytes
      def size_of(glyph_id)
        raise "Table not parsed. Call parse_with_context first." unless @offsets

        return nil if glyph_id >= num_glyphs || glyph_id.negative?

        offsets[glyph_id + 1] - offsets[glyph_id]
      end

      # Check if a glyph has no outline data
      #
      # A glyph is empty when its size is 0, which occurs when consecutive
      # offsets are equal. Empty glyphs are used for space characters and
      # other non-visible glyphs.
      #
      # @param glyph_id [Integer] Glyph ID (0-based)
      # @return [Boolean, nil] True if empty, false if has data, nil if invalid ID
      # @raise [RuntimeError] If table has not been parsed with context
      #
      # @example Checking if glyph is empty
      #   is_empty = loca.empty?(32)  # Check if space character is empty
      def empty?(glyph_id)
        size = size_of(glyph_id)
        size&.zero?
      end

      # Check if the table has been parsed with context
      #
      # @return [Boolean] True if parsed, false otherwise
      def parsed?
        !@offsets.nil?
      end

      # Check if using short format (format 0)
      #
      # @return [Boolean] True if short format, false otherwise
      def short_format?
        format == FORMAT_SHORT
      end

      # Check if using long format (format 1)
      #
      # @return [Boolean] True if long format, false otherwise
      def long_format?
        format == FORMAT_LONG
      end

      # Get the expected size for this table
      #
      # @return [Integer, nil] Expected size in bytes, or nil if not parsed
      def expected_size
        return nil unless parsed?

        offset_count = num_glyphs + 1
        if short_format?
          offset_count * 2  # uint16
        else
          offset_count * 4  # uint32
        end
      end

      private

      # Validate context parameters
      #
      # @param format [Integer] Format indicator
      # @param num_glyphs [Integer] Total glyphs
      # @raise [ArgumentError] If parameters are invalid
      def validate_context_params(format, num_glyphs)
        if format.nil? || (format != FORMAT_SHORT && format != FORMAT_LONG)
          raise ArgumentError,
                "indexToLocFormat must be 0 (short) or 1 (long), " \
                "got: #{format.inspect}"
        end

        if num_glyphs.nil? || num_glyphs < 1
          raise ArgumentError,
                "numGlyphs must be >= 1, got: #{num_glyphs.inspect}"
        end
      end

      # Parse short format offsets (uint16, multiply by 2)
      #
      # @param io [StringIO] Input stream
      # @param count [Integer] Number of offsets to parse
      # @return [Array<Integer>] Array of offsets
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_short_offsets(io, count)
        offsets = []
        count.times do |i|
          value = read_uint16(io)

          if value.nil?
            raise Fontisan::CorruptedTableError,
                  "Insufficient data for short offset at index #{i}"
          end

          # Short offsets are divided by 2, so multiply to get actual offset
          offsets << (value * 2)
        end
        offsets
      end

      # Parse long format offsets (uint32, use as-is)
      #
      # @param io [StringIO] Input stream
      # @param count [Integer] Number of offsets to parse
      # @return [Array<Integer>] Array of offsets
      # @raise [Fontisan::CorruptedTableError] If insufficient data
      def parse_long_offsets(io, count)
        offsets = []
        count.times do |i|
          value = read_uint32(io)

          if value.nil?
            raise Fontisan::CorruptedTableError,
                  "Insufficient data for long offset at index #{i}"
          end

          offsets << value
        end
        offsets
      end

      # Validate that all expected data was parsed
      #
      # @param io [StringIO] Input stream
      # @param offset_count [Integer] Expected number of offsets
      # @raise [Fontisan::CorruptedTableError] If data validation fails
      def validate_parsed_data!(io, offset_count)
        # Check that we parsed the expected number of offsets
        if offsets.length != offset_count
          raise Fontisan::CorruptedTableError,
                "Expected #{offset_count} offsets, got #{offsets.length}"
        end

        # Check that offsets are monotonically increasing
        offsets.each_cons(2).with_index do |(prev, curr), i|
          if curr < prev
            raise Fontisan::CorruptedTableError,
                  "Offsets are not monotonically increasing: " \
                  "offset[#{i}]=#{prev}, offset[#{i + 1}]=#{curr}"
          end
        end

        # Check for unexpected remaining data
        remaining = io.read
        if remaining && !remaining.empty? && remaining.length > 3
          # Some fonts may have padding, only warn if significant
          warn "Warning: loca table has #{remaining.length} unexpected " \
               "bytes after parsing"
        end
      end

      # Read unsigned 16-bit integer
      #
      # @param io [StringIO] Input stream
      # @return [Integer, nil] Value or nil if insufficient data
      def read_uint16(io)
        data = io.read(2)
        return nil if data.nil? || data.length < 2

        data.unpack1("n") # Big-endian unsigned 16-bit
      end

      # Read unsigned 32-bit integer
      #
      # @param io [StringIO] Input stream
      # @return [Integer, nil] Value or nil if insufficient data
      def read_uint32(io)
        data = io.read(4)
        return nil if data.nil? || data.length < 4

        data.unpack1("N") # Big-endian unsigned 32-bit
      end
    end
  end
end
