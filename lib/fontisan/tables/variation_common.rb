# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

module Fontisan
  module Tables
    # Shared structures for OpenType variation tables (HVAR, VVAR, MVAR, etc.)
    #
    # These structures are used across multiple variation tables to define
    # variation regions in design space and organize delta values that are
    # applied based on axis coordinates.
    #
    # Reference: OpenType specification, Variation Common Table Formats
    module VariationCommon
      # Variation region in design space
      #
      # A region is defined by ranges on one or more axes. Each region has a
      # scalar value (0.0 to 1.0) that determines how much its deltas contribute
      # based on the current design coordinates.
      class RegionAxisCoordinates < Binary::BaseRecord
        int16 :start_coord  # Start of region range (F2DOT14)
        int16 :peak_coord   # Peak value in range (F2DOT14)
        int16 :end_coord    # End of region range (F2DOT14)

        # Convert start coordinate from F2DOT14 to float
        #
        # @return [Float] Start coordinate value
        def start
          f2dot14_to_float(start_coord)
        end

        # Convert peak coordinate from F2DOT14 to float
        #
        # @return [Float] Peak coordinate value
        def peak
          f2dot14_to_float(peak_coord)
        end

        # Convert end coordinate from F2DOT14 to float
        #
        # @return [Float] End coordinate value
        def end_value
          f2dot14_to_float(end_coord)
        end

        private

        # Convert F2DOT14 fixed-point (2.14) to float
        #
        # @param value [Integer] F2DOT14 value
        # @return [Float] Floating-point value
        def f2dot14_to_float(value)
          # Handle signed 16-bit value
          signed = value > 0x7FFF ? value - 0x10000 : value
          signed / 16384.0
        end
      end

      # Variation region definition
      #
      # Defines a region in design space with coordinate ranges for each axis.
      class VariationRegion < Binary::BaseRecord
        # Region axis coordinates array - length determined by axis count
        # This is manually parsed by the parent VariationRegionList

        # Parse region axis coordinates
        #
        # @param data [String] Binary data
        # @param axis_count [Integer] Number of axes
        # @return [Array<RegionAxisCoordinates>] Axis coordinates
        def self.parse_coordinates(data, axis_count)
          io = StringIO.new(data)
          io.set_encoding(Encoding::BINARY)

          Array.new(axis_count) do
            coord_data = io.read(6) # 3 * int16
            next nil if coord_data.nil? || coord_data.bytesize < 6

            RegionAxisCoordinates.read(coord_data)
          end.compact
        end
      end

      # Variation region list
      #
      # Contains the regions used by variation data. Multiple variation tables
      # can reference the same region list.
      class VariationRegionList < Binary::BaseRecord
        uint16 :axis_count
        uint16 :region_count

        # Parse all variation regions
        #
        # @return [Array<Array<RegionAxisCoordinates>>] Array of regions
        def regions
          return @regions if @regions
          return @regions = [] if region_count.zero?

          data = raw_data
          offset = 4 # After axis_count and region_count

          @regions = Array.new(region_count) do |i|
            region_offset = offset + (i * axis_count * 6)
            region_size = axis_count * 6

            next nil if region_offset + region_size > data.bytesize

            region_data = data.byteslice(region_offset, region_size)
            VariationRegion.parse_coordinates(region_data, axis_count)
          end.compact
        end
      end

      # Item variation data
      #
      # Contains delta values for a set of items. Each item can have deltas
      # for multiple regions.
      class ItemVariationData < Binary::BaseRecord
        uint16 :item_count
        uint16 :short_delta_count
        uint16 :region_index_count

        # Parse region indices
        #
        # @return [Array<Integer>] Region indices
        def region_indices
          return @region_indices if @region_indices
          return @region_indices = [] if region_index_count.zero?

          data = raw_data
          offset = 6 # After header fields

          @region_indices = Array.new(region_index_count) do |i|
            idx_offset = offset + (i * 2)
            next nil if idx_offset + 2 > data.bytesize

            data.byteslice(idx_offset, 2).unpack1("n")
          end.compact
        end

        # Parse delta sets for all items
        #
        # @return [Array<Array<Integer>>] Delta sets for each item
        def delta_sets
          return @delta_sets if @delta_sets
          return @delta_sets = [] if item_count.zero?

          data = raw_data
          # Delta data starts after header and region indices
          offset = 6 + (region_index_count * 2)

          # Each item has region_index_count deltas
          # short_delta_count are int16, rest are int8
          long_count = region_index_count - short_delta_count

          # Safety check: long_count should not be negative
          if long_count.negative?
            warn "ItemVariationData parsing error: short_delta_count (#{short_delta_count}) > region_index_count (#{region_index_count})"
            return @delta_sets = []
          end

          @delta_sets = Array.new(item_count) do |i|
            item_offset = offset + (i * (short_delta_count * 2 + long_count))

            # Read short deltas (int16)
            shorts = Array.new(short_delta_count) do |j|
              delta_offset = item_offset + (j * 2)
              next nil if delta_offset + 2 > data.bytesize

              # Signed 16-bit
              value = data.byteslice(delta_offset, 2).unpack1("n")
              value > 0x7FFF ? value - 0x10000 : value
            end.compact

            # Read long deltas (int8)
            longs = Array.new(long_count) do |j|
              delta_offset = item_offset + (short_delta_count * 2) + j
              next nil if delta_offset + 1 > data.bytesize

              # Signed 8-bit
              value = data.byteslice(delta_offset, 1).unpack1("C")
              value > 0x7F ? value - 0x100 : value
            end.compact

            shorts + longs
          end
        end
      end

      # Item variation store
      #
      # Hierarchical storage for delta values. Contains variation data entries
      # and a region list that defines variation regions in design space.
      #
      # Used by: HVAR, VVAR, MVAR tables
      class ItemVariationStore < Binary::BaseRecord
        uint16 :format
        uint32 :variation_region_list_offset
        uint16 :item_variation_data_count

        # Parse variation region list
        #
        # @return [VariationRegionList, nil] Region list or nil
        def variation_region_list
          return @variation_region_list if defined?(@variation_region_list)
          return @variation_region_list = nil if variation_region_list_offset.zero?

          data = raw_data
          offset = variation_region_list_offset

          return @variation_region_list = nil if offset >= data.bytesize

          region_data = data.byteslice(offset..-1)
          @variation_region_list = VariationRegionList.read(region_data)
        rescue StandardError
          @variation_region_list = nil
        end

        # Parse item variation data offsets
        #
        # @return [Array<Integer>] Offsets to ItemVariationData
        def item_variation_data_offsets
          return @data_offsets if @data_offsets
          return @data_offsets = [] if item_variation_data_count.zero?

          data = raw_data
          offset = 8 # After header fields

          @data_offsets = Array.new(item_variation_data_count) do |i|
            offset_pos = offset + (i * 4)
            next nil if offset_pos + 4 > data.bytesize

            data.byteslice(offset_pos, 4).unpack1("N")
          end.compact
        end

        # Parse all item variation data entries
        #
        # @return [Array<ItemVariationData>] Variation data entries
        def item_variation_data_entries
          return @data_entries if @data_entries
          return @data_entries = [] if item_variation_data_count.zero?

          data = raw_data
          offsets = item_variation_data_offsets

          @data_entries = offsets.map do |data_offset|
            next nil if data_offset >= data.bytesize

            entry_data = data.byteslice(data_offset..-1)
            ItemVariationData.read(entry_data)
          end.compact
        rescue StandardError
          @data_entries = []
        end

        # Get delta set for specific item
        #
        # @param outer_index [Integer] Outer index (data entry)
        # @param inner_index [Integer] Inner index (item within entry)
        # @return [Array<Integer>, nil] Delta values or nil
        def delta_set(outer_index, inner_index)
          return nil if outer_index >= item_variation_data_count

          entry = item_variation_data_entries[outer_index]
          return nil if entry.nil? || inner_index >= entry.item_count

          entry.delta_sets[inner_index]
        end
      end

      # Delta set index mapping
      #
      # Maps glyph IDs to delta set indices in an ItemVariationStore.
      # Used for efficient lookup of variation data.
      class DeltaSetIndexMap < Binary::BaseRecord
        uint8 :format
        uint8 :entry_format

        # Get map data based on format
        #
        # @return [Array<Integer>] Map data
        def map_data
          return @map_data if @map_data

          data = raw_data

          case format
          when 0
            parse_format0(data)
          when 1
            parse_format1(data)
          else
            @map_data = []
          end
        end

        private

        # Parse format 0 map data
        def parse_format0(data)
          # Format 0: mapCount + mapData array
          return [] if data.bytesize < 4

          map_count = data.byteslice(2, 2).unpack1("n")

          # entry_format bits 4-5: outer size - 1, bits 0-3: inner size - 1
          outer_size = ((entry_format >> 4) & 0x3) + 1
          inner_size = (entry_format & 0xF) + 1
          entry_size = outer_size + inner_size

          @map_data = Array.new(map_count) do |i|
            offset = 4 + (i * entry_size)
            next nil if offset + entry_size > data.bytesize

            # Read entry and combine outer and inner indices
            # For simplicity, treat as combined integer
            case entry_size
            when 1
              data.byteslice(offset, 1).unpack1("C")
            when 2
              data.byteslice(offset, 2).unpack1("n")
            when 3
              bytes = data.byteslice(offset, 3).unpack("C3")
              (bytes[0] << 16) | (bytes[1] << 8) | bytes[2]
            when 4
              data.byteslice(offset, 4).unpack1("N")
            else
              # For larger sizes, read as big-endian integer
              bytes = data.byteslice(offset, entry_size).unpack("C*")
              bytes.reduce(0) { |acc, b| (acc << 8) | b }
            end
          end.compact
        end

        # Parse format 1 map data
        def parse_format1(_data)
          # Format 1: More complex with map count and data
          # Simplified implementation
          @map_data = []
        end
      end
    end
  end
end
