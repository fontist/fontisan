# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # sbix (Standard Bitmap Graphics) table parser
    #
    # The sbix table contains embedded bitmap graphics (PNG, JPEG, TIFF)
    # organized by strike sizes. This is Apple's format for color emoji.
    #
    # sbix Table Structure:
    # ```
    # sbix Table = Header (8 bytes)
    #            + Strike Offsets Array (4 bytes × numStrikes)
    #            + Strike Data (variable)
    # ```
    #
    # Header (8 bytes):
    # - version (uint16): Table version (1)
    # - flags (uint16): Flags (0)
    # - numStrikes (uint32): Number of bitmap strikes
    #
    # Each Strike contains:
    # - ppem (uint16): Pixels per em
    # - ppi (uint16): Pixels per inch (usually 72)
    # - glyphDataOffsets (uint32 × numGlyphs+1): Array of glyph data offsets
    # - glyph data records (variable)
    #
    # Glyph Data Record:
    # - originOffsetX (int16): X offset
    # - originOffsetY (int16): Y offset
    # - graphicType (uint32): 'png ', 'jpg ', 'tiff', 'dupe', 'mask'
    # - data (variable): Image data
    #
    # Reference: https://docs.microsoft.com/en-us/typography/opentype/spec/sbix
    #
    # @example Reading an sbix table
    #   data = font.table_data['sbix']
    #   sbix = Fontisan::Tables::Sbix.read(data)
    #   strikes = sbix.strikes
    #   png_data = sbix.glyph_data(42, 64)  # Get glyph 42 at 64 ppem
    class Sbix < Binary::BaseRecord
      # OpenType table tag for sbix
      TAG = "sbix"

      # Supported sbix version
      VERSION_1 = 1

      # Graphic type constants (4-byte ASCII codes)
      GRAPHIC_TYPE_PNG = 0x706E6720   # 'png '
      GRAPHIC_TYPE_JPG = 0x6A706720   # 'jpg '
      GRAPHIC_TYPE_TIFF = 0x74696666  # 'tiff'
      GRAPHIC_TYPE_DUPE = 0x64757065  # 'dupe'
      GRAPHIC_TYPE_MASK = 0x6D61736B  # 'mask'

      # Graphic type names
      GRAPHIC_TYPE_NAMES = {
        GRAPHIC_TYPE_PNG => "PNG",
        GRAPHIC_TYPE_JPG => "JPEG",
        GRAPHIC_TYPE_TIFF => "TIFF",
        GRAPHIC_TYPE_DUPE => "dupe",
        GRAPHIC_TYPE_MASK => "mask",
      }.freeze

      # @return [Integer] sbix version (should be 1)
      attr_reader :version

      # @return [Integer] Flags (reserved, should be 0)
      attr_reader :flags

      # @return [Integer] Number of bitmap strikes
      attr_reader :num_strikes

      # @return [Array<Integer>] Offsets to strike data from start of table
      attr_reader :strike_offsets

      # @return [Array<Hash>] Parsed strike records
      attr_reader :strikes

      # @return [String] Raw binary data for the entire sbix table
      attr_reader :raw_data

      # Override read to parse sbix structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Sbix] Parsed sbix table
      def self.read(io)
        sbix = new
        return sbix if io.nil?

        data = io.is_a?(String) ? io : io.read
        sbix.parse!(data)
        sbix
      end

      # Parse the sbix table structure
      #
      # @param data [String] Binary data for the sbix table
      # @raise [CorruptedTableError] If sbix structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse sbix header (8 bytes)
        parse_header(io)
        validate_header!

        # Parse strike offsets
        parse_strike_offsets(io)

        # Parse strike records
        parse_strikes
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse sbix table: #{e.message}"
      end

      # Get glyph data at specific ppem
      #
      # @param glyph_id [Integer] Glyph ID
      # @param ppem [Integer] Pixels per em
      # @return [Hash, nil] Glyph data hash with keys: :origin_x, :origin_y, :graphic_type, :data
      def glyph_data(glyph_id, ppem)
        strike = strike_for_ppem(ppem)
        return nil unless strike

        extract_glyph_data(strike, glyph_id)
      end

      # Get strike for specific ppem
      #
      # @param ppem [Integer] Pixels per em
      # @return [Hash, nil] Strike record or nil
      def strike_for_ppem(ppem)
        strikes&.find { |s| s[:ppem] == ppem }
      end

      # Get all ppem sizes
      #
      # @return [Array<Integer>] Sorted array of ppem sizes
      def ppem_sizes
        return [] unless strikes

        strikes.map { |s| s[:ppem] }.uniq.sort
      end

      # Check if glyph has bitmap at ppem
      #
      # @param glyph_id [Integer] Glyph ID
      # @param ppem [Integer] Pixels per em
      # @return [Boolean] True if glyph has bitmap
      def has_glyph_at_ppem?(glyph_id, ppem)
        data = glyph_data(glyph_id, ppem)
        !data.nil? && data[:data] && !data[:data].empty?
      end

      # Get supported graphic formats across all strikes
      #
      # @return [Array<String>] Array of format names (e.g., ["PNG", "JPEG"])
      def supported_formats
        return [] unless strikes

        formats = []
        strikes.each do |strike|
          # Sample first few glyphs to detect formats
          strike[:graphic_types]&.each do |type|
            format_name = GRAPHIC_TYPE_NAMES[type]
            formats << format_name if format_name && !["dupe",
                                                       "mask"].include?(format_name)
          end
        end
        formats.uniq.compact
      end

      # Validate the sbix table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if version.nil?
        return false if version != VERSION_1
        return false if num_strikes.nil? || num_strikes.negative?
        return false unless strikes

        true
      end

      private

      # Parse sbix header (8 bytes)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @version = io.read(2).unpack1("n")
        @flags = io.read(2).unpack1("n")
        @num_strikes = io.read(4).unpack1("N")
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless version == VERSION_1
          raise CorruptedTableError,
                "Unsupported sbix version: #{version} (only version 1 supported)"
        end

        if num_strikes.negative?
          raise CorruptedTableError,
                "Invalid numStrikes: #{num_strikes}"
        end
      end

      # Parse strike offsets array
      #
      # @param io [StringIO] Input stream
      def parse_strike_offsets(io)
        @strike_offsets = []
        return if num_strikes.zero?

        num_strikes.times do
          @strike_offsets << io.read(4).unpack1("N")
        end
      end

      # Parse all strike records
      #
      # The number of glyphs is calculated from offset differences
      def parse_strikes
        @strikes = []
        return if num_strikes.zero?

        strike_offsets.each_with_index do |offset, index|
          # Calculate strike size from offset difference
          next_offset = if index < num_strikes - 1
                          strike_offsets[index + 1]
                        else
                          raw_data.length
                        end

          strike = parse_strike(offset, next_offset - offset)
          @strikes << strike
        end
      end

      # Parse a single strike record
      #
      # @param offset [Integer] Offset from start of table
      # @param size [Integer] Size of strike data
      # @return [Hash] Strike record
      def parse_strike(offset, size)
        io = StringIO.new(raw_data)
        io.seek(offset)

        ppem = io.read(2).unpack1("n")
        ppi = io.read(2).unpack1("n")

        # Read glyph data offsets - they're relative to the start of the strike
        # The array is numGlyphs+1 long, with the last offset marking the end
        glyph_offsets = []

        # Keep reading offsets until we find the pattern
        # Offsets are relative to strike start, so they should be monotonically increasing
        loop do
          current_pos = io.pos
          break if current_pos >= offset + size

          offset_value = io.read(4)&.unpack1("N")
          break unless offset_value

          # If offset is beyond the strike size or smaller than previous, we've hit glyph data
          if glyph_offsets.any? && offset_value < glyph_offsets.last
            # Rewind - we read part of glyph data
            io.seek(current_pos)
            break
          end

          glyph_offsets << offset_value
        end

        num_glyphs = [glyph_offsets.length - 1, 0].max

        # Sample graphic types from first few glyphs
        graphic_types = sample_graphic_types(offset, glyph_offsets, size)

        {
          ppem: ppem,
          ppi: ppi,
          num_glyphs: num_glyphs,
          base_offset: offset,
          glyph_offsets: glyph_offsets,
          graphic_types: graphic_types,
        }
      end

      # Sample graphic types from first few glyphs
      #
      # @param strike_offset [Integer] Strike offset from table start
      # @param glyph_offsets [Array<Integer>] Glyph data offsets (relative to strike start)
      # @param strike_size [Integer] Total strike size
      # @return [Array<Integer>] Unique graphic type codes found
      def sample_graphic_types(strike_offset, glyph_offsets, strike_size)
        types = []
        return types if glyph_offsets.length < 2

        # Sample first 5 glyphs or all glyphs if fewer
        sample_count = [5, glyph_offsets.length - 1].min

        sample_count.times do |i|
          # Offsets are relative to strike start
          glyph_offset = glyph_offsets[i]
          next_glyph_offset = glyph_offsets[i + 1]

          # Check if offsets are valid
          next if glyph_offset >= strike_size || next_glyph_offset > strike_size
          next if next_glyph_offset <= glyph_offset # Empty glyph

          # Calculate absolute offset in table
          # glyph_offset is relative to strike start, so add strike_offset
          absolute_offset = strike_offset + glyph_offset
          next if absolute_offset + 8 > raw_data.length # Need at least header

          # Read graphic type (skip originOffsetX and originOffsetY = 4 bytes)
          io = StringIO.new(raw_data)
          io.seek(absolute_offset + 4)
          graphic_type = io.read(4)&.unpack1("N")
          types << graphic_type if graphic_type
        end

        types.compact.uniq
      end

      # Extract glyph data from strike
      #
      # @param strike [Hash] Strike record
      # @param glyph_id [Integer] Glyph ID
      # @return [Hash, nil] Glyph data or nil
      def extract_glyph_data(strike, glyph_id)
        return nil unless strike
        return nil if glyph_id >= strike[:num_glyphs]
        return nil unless strike[:glyph_offsets]
        return nil if glyph_id >= strike[:glyph_offsets].length - 1

        # Offsets are relative to strike start
        offset = strike[:glyph_offsets][glyph_id]
        next_offset = strike[:glyph_offsets][glyph_id + 1]

        return nil unless offset && next_offset
        return nil if next_offset <= offset # Empty glyph

        # Calculate absolute position in table
        absolute_offset = strike[:base_offset] + offset
        data_length = next_offset - offset

        # Need at least 8 bytes for glyph record header
        return nil if data_length < 8
        return nil if absolute_offset + data_length > raw_data.length

        # Parse glyph data record
        io = StringIO.new(raw_data)
        io.seek(absolute_offset)

        origin_x = io.read(2).unpack1("s>")  # int16 big-endian
        origin_y = io.read(2).unpack1("s>")  # int16 big-endian
        graphic_type = io.read(4).unpack1("N")

        # Remaining bytes are the actual image data
        image_data = io.read(data_length - 8)

        {
          origin_x: origin_x,
          origin_y: origin_y,
          graphic_type: graphic_type,
          graphic_type_name: GRAPHIC_TYPE_NAMES[graphic_type] || "unknown",
          data: image_data,
        }
      end
    end
  end
end
