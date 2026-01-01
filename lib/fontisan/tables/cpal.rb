# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # CPAL (Color Palette) table parser
    #
    # The CPAL table defines color palettes used by COLR layers. Each palette
    # contains an array of RGBA color values that can be referenced by the
    # COLR table's palette indices.
    #
    # CPAL Table Structure:
    # ```
    # CPAL Table = Header
    #            + Palette Indices Array
    #            + Color Records Array
    #            + [Palette Types Array] (version 1)
    #            + [Palette Labels Array] (version 1)
    #            + [Palette Entry Labels Array] (version 1)
    # ```
    #
    # Version 0 Header (12 bytes):
    # - version (uint16): Table version (0 or 1)
    # - numPaletteEntries (uint16): Number of colors per palette
    # - numPalettes (uint16): Number of palettes
    # - numColorRecords (uint16): Total number of color records
    # - colorRecordsArrayOffset (uint32): Offset to color records array
    #
    # Version 1 adds optional metadata for palette types and labels.
    #
    # Color Record Structure (4 bytes, BGRA format):
    # - blue (uint8)
    # - green (uint8)
    # - red (uint8)
    # - alpha (uint8)
    #
    # Reference: OpenType CPAL specification
    # https://docs.microsoft.com/en-us/typography/opentype/spec/cpal
    #
    # @example Reading a CPAL table
    #   data = font.table_data['CPAL']
    #   cpal = Fontisan::Tables::Cpal.read(data)
    #   palette = cpal.palette(0)  # Get first palette
    #   puts palette.colors.first  # => "#RRGGBBAA"
    class Cpal < Binary::BaseRecord
      # OpenType table tag for CPAL
      TAG = "CPAL"

      # @return [Integer] CPAL version (0 or 1)
      attr_reader :version

      # @return [Integer] Number of color entries per palette
      attr_reader :num_palette_entries

      # @return [Integer] Number of palettes in this table
      attr_reader :num_palettes

      # @return [Integer] Total number of color records
      attr_reader :num_color_records

      # @return [Integer] Offset to color records array
      attr_reader :color_records_array_offset

      # @return [String] Raw binary data for the entire CPAL table
      attr_reader :raw_data

      # @return [Array<Integer>] Palette indices (start index for each palette)
      attr_reader :palette_indices

      # @return [Array<Hash>] Parsed color records (RGBA hashes)
      attr_reader :color_records

      # Override read to parse CPAL structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Cpal] Parsed CPAL table
      def self.read(io)
        cpal = new
        return cpal if io.nil?

        data = io.is_a?(String) ? io : io.read
        cpal.parse!(data)
        cpal
      end

      # Parse the CPAL table structure
      #
      # @param data [String] Binary data for the CPAL table
      # @raise [CorruptedTableError] If CPAL structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse CPAL header
        parse_header(io)
        validate_header!

        # Parse palette indices array
        parse_palette_indices(io)

        # Parse color records
        parse_color_records(io)

        # Version 1 features (palette types, labels) not implemented yet
        # TODO: Add version 1 features in follow-up task
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse CPAL table: #{e.message}"
      end

      # Get a specific palette by index
      #
      # Returns an array of color strings in hex format (#RRGGBBAA).
      # Each palette contains num_palette_entries colors.
      #
      # @param index [Integer] Palette index (0-based)
      # @return [Array<String>, nil] Array of hex color strings, or nil if invalid
      def palette(index)
        return nil if index.negative? || index >= num_palettes

        # Get starting index for this palette
        start_index = palette_indices[index]

        # Extract colors for this palette
        colors = []
        num_palette_entries.times do |i|
          color_record = color_records[start_index + i]
          colors << color_to_hex(color_record) if color_record
        end

        colors
      end

      # Get all palettes
      #
      # @return [Array<Array<String>>] Array of palettes, each an array of hex colors
      def all_palettes
        (0...num_palettes).map { |i| palette(i) }
      end

      # Get color at specific palette and entry index
      #
      # @param palette_index [Integer] Palette index
      # @param entry_index [Integer] Entry index within palette
      # @return [String, nil] Hex color string or nil
      def color_at(palette_index, entry_index)
        return nil if palette_index.negative? || palette_index >= num_palettes
        return nil if entry_index.negative? || entry_index >= num_palette_entries

        start_index = palette_indices[palette_index]
        color_record = color_records[start_index + entry_index]
        color_record ? color_to_hex(color_record) : nil
      end

      # Validate the CPAL table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if version.nil?
        return false unless [0, 1].include?(version)
        return false if num_palette_entries.nil? || num_palette_entries.negative?
        return false if num_palettes.nil? || num_palettes.negative?
        return false if num_color_records.nil? || num_color_records.negative?
        return false unless palette_indices
        return false unless color_records

        true
      end

      private

      # Parse CPAL header (12 bytes for version 0, 16 bytes for version 1)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @version = io.read(2).unpack1("n")
        @num_palette_entries = io.read(2).unpack1("n")
        @num_palettes = io.read(2).unpack1("n")
        @num_color_records = io.read(2).unpack1("n")
        @color_records_array_offset = io.read(4).unpack1("N")

        # Version 1 has additional header fields
        if version == 1
          # TODO: Parse version 1 header fields
          # - paletteTypesArrayOffset (uint32)
          # - paletteLabelsArrayOffset (uint32)
          # - paletteEntryLabelsArrayOffset (uint32)
        end
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless [0, 1].include?(version)
          raise CorruptedTableError,
                "Unsupported CPAL version: #{version} (only versions 0 and 1 supported)"
        end

        if num_palette_entries.negative?
          raise CorruptedTableError,
                "Invalid numPaletteEntries: #{num_palette_entries}"
        end

        if num_palettes.negative?
          raise CorruptedTableError,
                "Invalid numPalettes: #{num_palettes}"
        end

        if num_color_records.negative?
          raise CorruptedTableError,
                "Invalid numColorRecords: #{num_color_records}"
        end

        # Validate that total color records match expected count
        expected_records = num_palettes * num_palette_entries
        unless num_color_records >= expected_records
          raise CorruptedTableError,
                "Insufficient color records: expected at least #{expected_records}, " \
                "got #{num_color_records}"
        end
      end

      # Parse palette indices array
      #
      # @param io [StringIO] Input stream
      def parse_palette_indices(io)
        @palette_indices = []
        return if num_palettes.zero?

        # Palette indices immediately follow header (at offset 12 for v0, 16 for v1)
        # Each index is uint16 (2 bytes)
        num_palettes.times do
          index = io.read(2).unpack1("n")
          @palette_indices << index
        end
      end

      # Parse color records array
      #
      # @param io [StringIO] Input stream
      def parse_color_records(io)
        @color_records = []
        return if num_color_records.zero?

        # Seek to color records array
        io.seek(color_records_array_offset)

        # Parse each color record (4 bytes, BGRA format)
        num_color_records.times do
          blue = io.read(1).unpack1("C")
          green = io.read(1).unpack1("C")
          red = io.read(1).unpack1("C")
          alpha = io.read(1).unpack1("C")

          @color_records << {
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
          }
        end
      end

      # Convert color record to hex string
      #
      # @param color [Hash] Color hash with :red, :green, :blue, :alpha keys
      # @return [String] Hex color string (#RRGGBBAA)
      def color_to_hex(color)
        format(
          "#%<red>02X%<green>02X%<blue>02X%<alpha>02X",
          red: color[:red],
          green: color[:green],
          blue: color[:blue],
          alpha: color[:alpha],
        )
      end
    end
  end
end
