# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # CBLC (Color Bitmap Location) table parser
    #
    # The CBLC table contains location information for bitmap glyphs at various
    # sizes (strikes). It works together with the CBDT table which contains the
    # actual bitmap data.
    #
    # CBLC Table Structure:
    # ```
    # CBLC Table = Header (8 bytes)
    #            + BitmapSize Records (48 bytes each)
    # ```
    #
    # Header (8 bytes):
    # - version (uint32): Table version (0x00020000 or 0x00030000)
    # - numSizes (uint32): Number of BitmapSize records
    #
    # Each BitmapSize record (48 bytes) contains:
    # - indexSubTableArrayOffset (uint32): Offset to index subtable array
    # - indexTablesSize (uint32): Size of index subtables
    # - numberOfIndexSubTables (uint32): Number of index subtables
    # - colorRef (uint32): Not used, set to 0
    # - hori (SbitLineMetrics, 12 bytes): Horizontal line metrics
    # - vert (SbitLineMetrics, 12 bytes): Vertical line metrics
    # - startGlyphIndex (uint16): First glyph ID in strike
    # - endGlyphIndex (uint16): Last glyph ID in strike
    # - ppemX (uint8): Horizontal pixels per em
    # - ppemY (uint8): Vertical pixels per em
    # - bitDepth (uint8): Bit depth (1, 2, 4, 8, 32)
    # - flags (int8): Flags
    #
    # Reference: OpenType CBLC specification
    # https://docs.microsoft.com/en-us/typography/opentype/spec/cblc
    #
    # @example Reading a CBLC table
    #   data = font.table_data['CBLC']
    #   cblc = Fontisan::Tables::Cblc.read(data)
    #   strikes = cblc.strikes
    #   puts "Font has #{strikes.length} bitmap strikes"
    class Cblc < Binary::BaseRecord
      # OpenType table tag for CBLC
      TAG = "CBLC"

      # Supported CBLC versions
      VERSION_2_0 = 0x00020000
      VERSION_3_0 = 0x00030000

      # SbitLineMetrics structure (12 bytes)
      #
      # Contains metrics for horizontal or vertical layout
      class SbitLineMetrics < Binary::BaseRecord
        endian :big
        int8 :ascender
        int8 :descender
        uint8 :width_max
        int8 :caret_slope_numerator
        int8 :caret_slope_denominator
        int8 :caret_offset
        int8 :min_origin_sb
        int8 :min_advance_sb
        int8 :max_before_bl
        int8 :min_after_bl
        int8 :pad1
        int8 :pad2
      end

      # BitmapSize record structure (48 bytes)
      #
      # Describes a bitmap strike at a specific ppem size
      class BitmapSize < Binary::BaseRecord
        endian :big
        uint32 :index_subtable_array_offset
        uint32 :index_tables_size
        uint32 :number_of_index_subtables
        uint32 :color_ref

        # Read the SbitLineMetrics structures manually
        def self.read(io)
          data = io.is_a?(String) ? io : io.read
          size = new

          io = StringIO.new(data)
          size.instance_variable_set(:@index_subtable_array_offset, io.read(4).unpack1("N"))
          size.instance_variable_set(:@index_tables_size, io.read(4).unpack1("N"))
          size.instance_variable_set(:@number_of_index_subtables, io.read(4).unpack1("N"))
          size.instance_variable_set(:@color_ref, io.read(4).unpack1("N"))

          # Parse hori and vert metrics (12 bytes each)
          hori_data = io.read(12)
          vert_data = io.read(12)
          size.instance_variable_set(:@hori, SbitLineMetrics.read(hori_data))
          size.instance_variable_set(:@vert, SbitLineMetrics.read(vert_data))

          # Parse remaining fields
          size.instance_variable_set(:@start_glyph_index, io.read(2).unpack1("n"))
          size.instance_variable_set(:@end_glyph_index, io.read(2).unpack1("n"))
          size.instance_variable_set(:@ppem_x, io.read(1).unpack1("C"))
          size.instance_variable_set(:@ppem_y, io.read(1).unpack1("C"))
          size.instance_variable_set(:@bit_depth, io.read(1).unpack1("C"))
          size.instance_variable_set(:@flags, io.read(1).unpack1("c"))

          size
        end

        attr_reader :index_subtable_array_offset, :index_tables_size,
                    :number_of_index_subtables, :color_ref, :hori, :vert,
                    :start_glyph_index, :end_glyph_index, :ppem_x, :ppem_y,
                    :bit_depth, :flags

        # Get ppem size (assumes square pixels)
        #
        # @return [Integer] Pixels per em
        def ppem
          ppem_x
        end

        # Get glyph range for this strike
        #
        # @return [Range] Range of glyph IDs
        def glyph_range
          start_glyph_index..end_glyph_index
        end

        # Check if this strike includes a specific glyph ID
        #
        # @param glyph_id [Integer] Glyph ID to check
        # @return [Boolean] True if glyph is in range
        def includes_glyph?(glyph_id)
          glyph_range.include?(glyph_id)
        end
      end

      # @return [Integer] CBLC version
      attr_reader :version

      # @return [Integer] Number of bitmap size records
      attr_reader :num_sizes

      # @return [Array<BitmapSize>] Parsed bitmap size records
      attr_reader :bitmap_sizes

      # @return [String] Raw binary data for the entire CBLC table
      attr_reader :raw_data

      # Override read to parse CBLC structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Cblc] Parsed CBLC table
      def self.read(io)
        cblc = new
        return cblc if io.nil?

        data = io.is_a?(String) ? io : io.read
        cblc.parse!(data)
        cblc
      end

      # Parse the CBLC table structure
      #
      # @param data [String] Binary data for the CBLC table
      # @raise [CorruptedTableError] If CBLC structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse CBLC header (8 bytes)
        parse_header(io)
        validate_header!

        # Parse bitmap size records
        parse_bitmap_sizes(io)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse CBLC table: #{e.message}"
      end

      # Get bitmap strikes (sizes)
      #
      # @return [Array<BitmapSize>] Array of bitmap strikes
      def strikes
        bitmap_sizes || []
      end

      # Get strikes for specific ppem size
      #
      # @param ppem [Integer] Pixels per em
      # @return [Array<BitmapSize>] Strikes matching ppem
      def strikes_for_ppem(ppem)
        strikes.select { |size| size.ppem == ppem }
      end

      # Check if glyph has bitmap at ppem size
      #
      # @param glyph_id [Integer] Glyph ID
      # @param ppem [Integer] Pixels per em
      # @return [Boolean] True if glyph has bitmap
      def has_bitmap_for_glyph?(glyph_id, ppem)
        strikes_for_ppem(ppem).any? do |strike|
          strike.includes_glyph?(glyph_id)
        end
      end

      # Get all available ppem sizes
      #
      # @return [Array<Integer>] Sorted array of ppem sizes
      def ppem_sizes
        strikes.map(&:ppem).uniq.sort
      end

      # Get all glyph IDs that have bitmaps across all strikes
      #
      # @return [Array<Integer>] Array of glyph IDs
      def glyph_ids_with_bitmaps
        strikes.flat_map { |strike| strike.glyph_range.to_a }.uniq.sort
      end

      # Get strikes that include a specific glyph ID
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<BitmapSize>] Strikes containing glyph
      def strikes_for_glyph(glyph_id)
        strikes.select { |strike| strike.includes_glyph?(glyph_id) }
      end

      # Get the number of bitmap strikes
      #
      # @return [Integer] Number of strikes
      def num_strikes
        num_sizes || 0
      end

      # Validate the CBLC table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if version.nil?
        return false unless [VERSION_2_0, VERSION_3_0].include?(version)
        return false if num_sizes.nil? || num_sizes.negative?
        return false unless bitmap_sizes

        true
      end

      private

      # Parse CBLC header (8 bytes)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @version = io.read(4).unpack1("N")
        @num_sizes = io.read(4).unpack1("N")
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless [VERSION_2_0, VERSION_3_0].include?(version)
          raise CorruptedTableError,
                "Unsupported CBLC version: 0x#{version.to_s(16).upcase} " \
                "(only versions 2.0 and 3.0 supported)"
        end

        if num_sizes.negative?
          raise CorruptedTableError,
                "Invalid numSizes: #{num_sizes}"
        end
      end

      # Parse bitmap size records
      #
      # @param io [StringIO] Input stream
      def parse_bitmap_sizes(io)
        @bitmap_sizes = []
        return if num_sizes.zero?

        # Each BitmapSize record is 48 bytes
        num_sizes.times do
          size_data = io.read(48)
          @bitmap_sizes << BitmapSize.read(size_data)
        end
      end
    end
  end
end
