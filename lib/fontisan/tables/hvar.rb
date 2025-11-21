# frozen_string_literal: true

require_relative "../binary/base_record"
require_relative "variation_common"

module Fontisan
  module Tables
    # Parser for the 'HVAR' (Horizontal Metrics Variations) table
    #
    # The HVAR table provides variation data for horizontal metrics including:
    # - Advance width variations
    # - Left side bearing (LSB) variations
    #
    # This table uses the ItemVariationStore structure to efficiently store
    # delta values for different regions in the design space.
    #
    # Reference: OpenType specification, HVAR table
    #
    # @example Reading an HVAR table
    #   data = font.table_data("HVAR")
    #   hvar = Fontisan::Tables::Hvar.read(data)
    #   advance_deltas = hvar.advance_width_deltas(glyph_id, coordinates)
    class Hvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint32 :item_variation_store_offset
      uint32 :advance_width_mapping_offset
      uint32 :lsb_mapping_offset
      uint32 :rsb_mapping_offset

      # Get version as a float
      #
      # @return [Float] Version number (e.g., 1.0)
      def version
        major_version + (minor_version / 10.0)
      end

      # Parse the item variation store
      #
      # @return [VariationCommon::ItemVariationStore, nil] Variation store
      def item_variation_store
        return @item_variation_store if defined?(@item_variation_store)
        return @item_variation_store = nil if item_variation_store_offset.zero?

        data = raw_data
        offset = item_variation_store_offset

        return @item_variation_store = nil if offset >= data.bytesize

        store_data = data.byteslice(offset..-1)
        @item_variation_store = VariationCommon::ItemVariationStore.read(store_data)
      rescue StandardError => e
        warn "Failed to parse HVAR item variation store: #{e.message}"
        @item_variation_store = nil
      end

      # Parse advance width mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] Advance width map
      def advance_width_mapping
        return @advance_width_mapping if defined?(@advance_width_mapping)
        return @advance_width_mapping = nil if advance_width_mapping_offset.zero?

        data = raw_data
        offset = advance_width_mapping_offset

        return @advance_width_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @advance_width_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse HVAR advance width mapping: #{e.message}"
        @advance_width_mapping = nil
      end

      # Parse LSB (left side bearing) mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] LSB map
      def lsb_mapping
        return @lsb_mapping if defined?(@lsb_mapping)
        return @lsb_mapping = nil if lsb_mapping_offset.zero?

        data = raw_data
        offset = lsb_mapping_offset

        return @lsb_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @lsb_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse HVAR LSB mapping: #{e.message}"
        @lsb_mapping = nil
      end

      # Parse RSB (right side bearing) mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] RSB map
      def rsb_mapping
        return @rsb_mapping if defined?(@rsb_mapping)
        return @rsb_mapping = nil if rsb_mapping_offset.zero?

        data = raw_data
        offset = rsb_mapping_offset

        return @rsb_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @rsb_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse HVAR RSB mapping: #{e.message}"
        @rsb_mapping = nil
      end

      # Get advance width delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def advance_width_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if advance_width_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = advance_width_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
      end

      # Get LSB delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def lsb_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if lsb_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = lsb_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
      end

      # Get RSB delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def rsb_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if rsb_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = rsb_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
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
