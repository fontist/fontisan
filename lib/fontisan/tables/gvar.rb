# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Parser for the 'gvar' (Glyph Variations) table
    #
    # The gvar table provides variation data for glyph outlines in TrueType
    # variable fonts. It contains delta values for each glyph's control points
    # that are applied based on the current design space coordinates.
    #
    # Unlike HVAR/VVAR/MVAR which use ItemVariationStore, gvar uses a
    # TupleVariationStore structure with packed delta values.
    #
    # Reference: OpenType specification, gvar table
    #
    # @example Reading a gvar table
    #   data = font.table_data("gvar")
    #   gvar = Fontisan::Tables::Gvar.read(data)
    #   deltas = gvar.glyph_variations(glyph_id)
    class Gvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint16 :axis_count
      uint16 :shared_tuple_count
      uint32 :shared_tuples_offset
      uint16 :glyph_count
      uint16 :flags
      uint32 :glyph_variation_data_array_offset

      # Flags
      SHARED_POINT_NUMBERS = 0x8000
      LONG_OFFSETS = 0x0001

      # Tuple variation header
      class TupleVariationHeader < Binary::BaseRecord
        uint16 :variation_data_size
        uint16 :tuple_index

        # Tuple index flags
        EMBEDDED_PEAK_TUPLE = 0x8000
        INTERMEDIATE_REGION = 0x4000
        PRIVATE_POINT_NUMBERS = 0x2000
        TUPLE_INDEX_MASK = 0x0FFF

        # Check if tuple has embedded peak coordinates
        #
        # @return [Boolean] True if embedded
        def embedded_peak_tuple?
          (tuple_index & EMBEDDED_PEAK_TUPLE) != 0
        end

        # Check if tuple has intermediate region
        #
        # @return [Boolean] True if intermediate region
        def intermediate_region?
          (tuple_index & INTERMEDIATE_REGION) != 0
        end

        # Check if tuple has private point numbers
        #
        # @return [Boolean] True if private points
        def private_point_numbers?
          (tuple_index & PRIVATE_POINT_NUMBERS) != 0
        end

        # Get shared tuple index
        #
        # @return [Integer] Tuple index
        def shared_tuple_index
          tuple_index & TUPLE_INDEX_MASK
        end
      end

      # Get version as a float
      #
      # @return [Float] Version number (e.g., 1.0)
      def version
        major_version + (minor_version / 10.0)
      end

      # Check if using long offsets
      #
      # @return [Boolean] True if long offsets
      def long_offsets?
        (flags & LONG_OFFSETS) != 0
      end

      # Check if using shared point numbers
      #
      # @return [Boolean] True if shared points
      def shared_point_numbers?
        (flags & SHARED_POINT_NUMBERS) != 0
      end

      # Parse shared tuples
      #
      # @return [Array<Array<Integer>>] Shared peak tuples
      def shared_tuples
        return @shared_tuples if @shared_tuples
        return @shared_tuples = [] if shared_tuple_count.zero?

        data = raw_data
        offset = shared_tuples_offset

        return @shared_tuples = [] if offset >= data.bytesize

        @shared_tuples = Array.new(shared_tuple_count) do |i|
          tuple_offset = offset + (i * axis_count * 2)

          Array.new(axis_count) do |j|
            coord_offset = tuple_offset + (j * 2)
            next nil if coord_offset + 2 > data.bytesize

            # F2DOT14 format
            value = data.byteslice(coord_offset, 2).unpack1("n")
            signed = value > 0x7FFF ? value - 0x10000 : value
            signed / 16384.0
          end.compact
        end.compact
      end

      # Parse glyph variation data offsets
      #
      # @return [Array<Integer>] Array of offsets
      def glyph_variation_data_offsets
        return @glyph_offsets if @glyph_offsets

        data = raw_data
        # Offsets start after the header (20 bytes)
        offset = 20

        offset_size = long_offsets? ? 4 : 2
        offset_count = glyph_count + 1 # One extra for the end

        @glyph_offsets = Array.new(offset_count) do |i|
          offset_pos = offset + (i * offset_size)
          next nil if offset_pos + offset_size > data.bytesize

          raw_offset = if long_offsets?
                         data.byteslice(offset_pos, 4).unpack1("N")
                       else
                         data.byteslice(offset_pos, 2).unpack1("n") * 2
                       end

          glyph_variation_data_array_offset + raw_offset
        end.compact
      end

      # Get variation data for a specific glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [String, nil] Raw variation data or nil
      def glyph_variation_data(glyph_id)
        return nil if glyph_id >= glyph_count

        offsets = glyph_variation_data_offsets
        return nil if glyph_id >= offsets.length - 1

        start_offset = offsets[glyph_id]
        end_offset = offsets[glyph_id + 1]

        return nil if start_offset == end_offset # No data

        data = raw_data
        return nil if end_offset > data.bytesize

        data.byteslice(start_offset, end_offset - start_offset)
      end

      # Parse tuple variation headers for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Hash>, nil] Array of tuple info or nil
      def glyph_tuple_variations(glyph_id)
        var_data = glyph_variation_data(glyph_id)
        return nil if var_data.nil? || var_data.empty?

        io = StringIO.new(var_data)
        io.set_encoding(Encoding::BINARY)

        # Read header
        tuple_count_and_offset = io.read(4).unpack1("N")
        tuple_count = tuple_count_and_offset >> 16
        data_offset = tuple_count_and_offset & 0xFFFF

        # Check for shared point numbers
        has_shared_points = (tuple_count & 0x8000) != 0
        tuple_count &= 0x0FFF

        return [] if tuple_count.zero?

        # Parse each tuple
        tuples = []
        tuple_count.times do
          header_data = io.read(4)
          break if header_data.nil? || header_data.bytesize < 4

          header = TupleVariationHeader.read(header_data)

          tuple_info = {
            data_size: header.variation_data_size,
            embedded_peak: header.embedded_peak_tuple?,
            intermediate: header.intermediate_region?,
            private_points: header.private_point_numbers?,
            shared_index: header.shared_tuple_index,
          }

          # Read peak tuple if embedded
          if header.embedded_peak_tuple?
            peak = Array.new(axis_count) do
              coord_data = io.read(2)
              break nil if coord_data.nil?

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end
            tuple_info[:peak] = peak.compact
          end

          # Read intermediate region if present
          if header.intermediate_region?
            start_tuple = Array.new(axis_count) do
              coord_data = io.read(2)
              break nil if coord_data.nil?

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end

            end_tuple = Array.new(axis_count) do
              coord_data = io.read(2)
              break nil if coord_data.nil?

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end

            tuple_info[:start] = start_tuple.compact
            tuple_info[:end] = end_tuple.compact
          end

          tuples << tuple_info
        end

        {
          tuple_count: tuple_count,
          has_shared_points: has_shared_points,
          data_offset: data_offset,
          tuples: tuples,
        }
      rescue StandardError => e
        warn "Failed to parse glyph tuple variations: #{e.message}"
        nil
      end

      # Check if table is valid
      #
      # @return [Boolean] True if valid
      def valid?
        major_version == 1 && minor_version.zero?
      end
    end
  end
end
