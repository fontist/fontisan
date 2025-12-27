# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"
require_relative "../variation/tuple_variation_header"

module Fontisan
  module Tables
    # Parser for the 'cvar' (CVT Variations) table
    #
    # The cvar table provides variation data for the Control Value Table (CVT)
    # in TrueType variable fonts with hinting. The CVT contains scalar values
    # that are referenced by TrueType instructions for grid-fitting.
    #
    # Like gvar, this table uses a TupleVariationStore structure with packed
    # delta values rather than ItemVariationStore.
    #
    # Reference: OpenType specification, cvar table
    #
    # @example Reading a cvar table
    #   data = font.table_data("cvar")
    #   cvar = Fontisan::Tables::Cvar.read(data)
    #   cvt_deltas = cvar.cvt_variations
    class Cvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint16 :tuple_variation_count
      uint16 :data_offset

      # Get version as a float
      #
      # @return [Float] Version number (e.g., 1.0)
      def version
        major_version + (minor_version / 10.0)
      end

      # Get tuple count
      #
      # @return [Integer] Number of tuple variations
      def tuple_count
        tuple_variation_count & 0x0FFF
      end

      # Check if using shared point numbers
      #
      # @return [Boolean] True if shared points
      def shared_point_numbers?
        (tuple_variation_count & 0x8000) != 0
      end

      # Get axis count from fvar table (needs to be provided externally)
      # This is a placeholder that should be set by the caller
      attr_accessor :axis_count

      # Parse tuple variation headers
      #
      # @return [Array<Hash>] Array of tuple information
      def tuple_variations
        return @tuple_variations if @tuple_variations
        return @tuple_variations = [] if tuple_count.zero?

        data = raw_data
        # Tuple records start after header (8 bytes)
        offset = 8

        count = tuple_count
        tuples = []

        count.times do |_i|
          break if offset + 4 > data.bytesize

          header_data = data.byteslice(offset, 4)
          header = Variation::TupleVariationHeader.read(header_data)
          offset += 4

          tuple_info = {
            data_size: header.variation_data_size,
            embedded_peak: header.embedded_peak_tuple?,
            intermediate: header.intermediate_region?,
            private_points: header.private_point_numbers?,
            shared_index: header.shared_tuple_index,
          }

          # Read peak tuple if embedded
          if header.embedded_peak_tuple? && axis_count
            peak = Array.new(axis_count) do
              next nil if offset + 2 > data.bytesize

              coord_data = data.byteslice(offset, 2)
              offset += 2

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end.compact
            tuple_info[:peak] = peak
          end

          # Read intermediate region if present
          if header.intermediate_region? && axis_count
            start_tuple = Array.new(axis_count) do
              next nil if offset + 2 > data.bytesize

              coord_data = data.byteslice(offset, 2)
              offset += 2

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end.compact

            end_tuple = Array.new(axis_count) do
              next nil if offset + 2 > data.bytesize

              coord_data = data.byteslice(offset, 2)
              offset += 2

              value = coord_data.unpack1("n")
              signed = value > 0x7FFF ? value - 0x10000 : value
              signed / 16384.0
            end.compact

            tuple_info[:start] = start_tuple
            tuple_info[:end] = end_tuple
          end

          tuples << tuple_info
        end

        @tuple_variations = tuples
      rescue StandardError => e
        warn "Failed to parse cvar tuple variations: #{e.message}"
        @tuple_variations = []
      end

      # Get variation data section
      #
      # @return [String, nil] Raw variation data
      def variation_data
        return @variation_data if defined?(@variation_data)

        data = raw_data
        offset = data_offset

        return @variation_data = nil if offset >= data.bytesize

        @variation_data = data.byteslice(offset..-1)
      end

      # Parse CVT deltas for a specific tuple
      #
      # This is a simplified parser that returns the raw delta data.
      # Full delta unpacking would require knowing point counts and
      # delta formats.
      #
      # @param tuple_index [Integer] Tuple index
      # @return [Hash, nil] Tuple info with data offset
      def tuple_variation_data(tuple_index)
        return nil if tuple_index >= tuple_count

        tuples = tuple_variations
        return nil if tuple_index >= tuples.length

        tuple = tuples[tuple_index]

        # Calculate data offset for this tuple
        # This is complex and requires walking through all previous tuples
        # For now, return tuple metadata
        {
          tuple: tuple,
          data_size: tuple[:data_size],
        }
      end

      # Get summary of CVT variations
      #
      # @return [Hash] Summary information
      def summary
        {
          version: version,
          tuple_count: tuple_count,
          shared_points: shared_point_numbers?,
          data_offset: data_offset,
          tuples: tuple_variations.map do |t|
            {
              embedded_peak: t[:embedded_peak],
              intermediate: t[:intermediate],
              private_points: t[:private_points],
              peak: t[:peak],
            }
          end,
        }
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
