# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # COLR (Color) table parser
    #
    # The COLR table defines layered color glyphs where each layer references
    # a glyph ID and a palette index from the CPAL table. This enables fonts
    # to display multi-colored glyphs such as emoji or brand logos.
    #
    # COLR Table Structure:
    # ```
    # COLR Table = Header (14 bytes)
    #            + Base Glyph Records (6 bytes each)
    #            + Layer Records (4 bytes each)
    # ```
    #
    # Version 0 Structure:
    # - version (uint16): Table version (0)
    # - numBaseGlyphRecords (uint16): Number of base glyphs
    # - baseGlyphRecordsOffset (uint32): Offset to base glyph records array
    # - layerRecordsOffset (uint32): Offset to layer records array
    # - numLayerRecords (uint16): Number of layer records
    #
    # The COLR table must be used together with the CPAL (Color Palette) table
    # which defines the actual RGB color values referenced by palette indices.
    #
    # Reference: OpenType COLR specification
    # https://docs.microsoft.com/en-us/typography/opentype/spec/colr
    #
    # @example Reading a COLR table
    #   data = font.table_data['COLR']
    #   colr = Fontisan::Tables::Colr.read(data)
    #   layers = colr.layers_for_glyph(42)
    #   puts "Glyph 42 has #{layers.length} color layers"
    class Colr < Binary::BaseRecord
      # OpenType table tag for COLR
      TAG = "COLR"

      # Base Glyph Record structure for COLR table
      #
      # Each base glyph record associates a glyph ID with its color layers.
      # Structure (6 bytes): glyph_id, first_layer_index, num_layers
      class BaseGlyphRecord < Binary::BaseRecord
        endian :big
        uint16 :glyph_id
        uint16 :first_layer_index
        uint16 :num_layers

        def has_layers?
          num_layers.positive?
        end
      end

      # Layer Record structure for COLR table
      #
      # Each layer record specifies a glyph and palette index.
      # Structure (4 bytes): glyph_id, palette_index
      class LayerRecord < Binary::BaseRecord
        endian :big
        FOREGROUND_COLOR = 0xFFFF

        uint16 :glyph_id
        uint16 :palette_index

        def uses_foreground_color?
          palette_index == FOREGROUND_COLOR
        end

        def uses_palette_color?
          !uses_foreground_color?
        end
      end

      # @return [Integer] COLR version (0 for version 0)
      attr_reader :version

      # @return [Integer] Number of base glyph records
      attr_reader :num_base_glyph_records

      # @return [Integer] Offset to base glyph records array
      attr_reader :base_glyph_records_offset

      # @return [Integer] Offset to layer records array
      attr_reader :layer_records_offset

      # @return [Integer] Number of layer records
      attr_reader :num_layer_records

      # @return [String] Raw binary data for the entire COLR table
      attr_reader :raw_data

      # @return [Array<BaseGlyphRecord>] Parsed base glyph records
      attr_reader :base_glyph_records

      # @return [Array<LayerRecord>] Parsed layer records
      attr_reader :layer_records

      # Override read to parse COLR structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Colr] Parsed COLR table
      def self.read(io)
        colr = new
        return colr if io.nil?

        data = io.is_a?(String) ? io : io.read
        colr.parse!(data)
        colr
      end

      # Parse the COLR table structure
      #
      # @param data [String] Binary data for the COLR table
      # @raise [CorruptedTableError] If COLR structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse COLR header (14 bytes)
        parse_header(io)
        validate_header!

        # Parse base glyph records
        parse_base_glyph_records(io)

        # Parse layer records
        parse_layer_records(io)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse COLR table: #{e.message}"
      end

      # Get color layers for a specific glyph ID
      #
      # Returns an array of LayerRecord objects for the specified glyph.
      # Returns empty array if glyph has no color layers.
      #
      # @param glyph_id [Integer] Glyph ID to look up
      # @return [Array<LayerRecord>] Array of layer records for this glyph
      def layers_for_glyph(glyph_id)
        # Find base glyph record for this glyph ID
        base_record = find_base_glyph_record(glyph_id)
        return [] unless base_record

        # Extract layers for this glyph
        first_index = base_record.first_layer_index
        num_layers = base_record.num_layers

        return [] if num_layers.zero?

        # Return slice of layer records
        layer_records[first_index, num_layers] || []
      end

      # Check if COLR table has color data for a specific glyph
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph has color layers
      def has_color_glyph?(glyph_id)
        !layers_for_glyph(glyph_id).empty?
      end

      # Get all glyph IDs that have color data
      #
      # @return [Array<Integer>] Array of glyph IDs with color layers
      def color_glyph_ids
        base_glyph_records.map(&:glyph_id)
      end

      # Get the number of color glyphs in this table
      #
      # @return [Integer] Number of base glyphs
      def num_color_glyphs
        num_base_glyph_records
      end

      # Validate the COLR table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false if version.nil?
        return false if version != 0 # Only version 0 supported currently
        return false if num_base_glyph_records.nil? || num_base_glyph_records.negative?
        return false if num_layer_records.nil? || num_layer_records.negative?
        return false unless base_glyph_records
        return false unless layer_records

        true
      end

      private

      # Parse COLR header (14 bytes)
      #
      # @param io [StringIO] Input stream
      def parse_header(io)
        @version = io.read(2).unpack1("n")
        @num_base_glyph_records = io.read(2).unpack1("n")
        @base_glyph_records_offset = io.read(4).unpack1("N")
        @layer_records_offset = io.read(4).unpack1("N")
        @num_layer_records = io.read(2).unpack1("n")
      end

      # Validate header values
      #
      # @raise [CorruptedTableError] If validation fails
      def validate_header!
        unless version.zero?
          raise CorruptedTableError,
                "Unsupported COLR version: #{version} (only version 0 supported)"
        end

        if num_base_glyph_records.negative?
          raise CorruptedTableError,
                "Invalid numBaseGlyphRecords: #{num_base_glyph_records}"
        end

        if num_layer_records.negative?
          raise CorruptedTableError,
                "Invalid numLayerRecords: #{num_layer_records}"
        end
      end

      # Parse base glyph records array
      #
      # @param io [StringIO] Input stream
      def parse_base_glyph_records(io)
        @base_glyph_records = []
        return if num_base_glyph_records.zero?

        # Seek to base glyph records
        io.seek(base_glyph_records_offset)

        # Parse each base glyph record (6 bytes each)
        num_base_glyph_records.times do
          record_data = io.read(6)
          record = BaseGlyphRecord.read(record_data)
          @base_glyph_records << record
        end
      end

      # Parse layer records array
      #
      # @param io [StringIO] Input stream
      def parse_layer_records(io)
        @layer_records = []
        return if num_layer_records.zero?

        # Seek to layer records
        io.seek(layer_records_offset)

        # Parse each layer record (4 bytes each)
        num_layer_records.times do
          record_data = io.read(4)
          record = LayerRecord.read(record_data)
          @layer_records << record
        end
      end

      # Find base glyph record for a specific glyph ID
      #
      # Uses binary search since base glyph records are sorted by glyph ID
      #
      # @param glyph_id [Integer] Glyph ID to find
      # @return [BaseGlyphRecord, nil] Base glyph record or nil if not found
      def find_base_glyph_record(glyph_id)
        # Binary search through base glyph records
        left = 0
        right = base_glyph_records.length - 1

        while left <= right
          mid = (left + right) / 2
          record = base_glyph_records[mid]

          if record.glyph_id == glyph_id
            return record
          elsif record.glyph_id < glyph_id
            left = mid + 1
          else
            right = mid - 1
          end
        end

        nil
      end
    end
  end
end
