# frozen_string_literal: true

require_relative "../binary/base_record"
require_relative "variation_common"

module Fontisan
  module Tables
    # Parser for the 'VVAR' (Vertical Metrics Variations) table
    #
    # The VVAR table provides variation data for vertical metrics including:
    # - Advance height variations
    # - Top side bearing (TSB) variations
    #
    # This table uses the ItemVariationStore structure to efficiently store
    # delta values for different regions in the design space.
    #
    # Reference: OpenType specification, VVAR table
    #
    # @example Reading a VVAR table
    #   data = font.table_data("VVAR")
    #   vvar = Fontisan::Tables::Vvar.read(data)
    #   advance_deltas = vvar.advance_height_deltas(glyph_id, coordinates)
    class Vvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint32 :item_variation_store_offset
      uint32 :advance_height_mapping_offset
      uint32 :tsb_mapping_offset
      uint32 :bsb_mapping_offset
      uint32 :v_org_mapping_offset

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
        warn "Failed to parse VVAR item variation store: #{e.message}"
        @item_variation_store = nil
      end

      # Parse advance height mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] Advance height map
      def advance_height_mapping
        return @advance_height_mapping if defined?(@advance_height_mapping)
        return @advance_height_mapping = nil if advance_height_mapping_offset.zero?

        data = raw_data
        offset = advance_height_mapping_offset

        return @advance_height_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @advance_height_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse VVAR advance height mapping: #{e.message}"
        @advance_height_mapping = nil
      end

      # Parse TSB (top side bearing) mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] TSB map
      def tsb_mapping
        return @tsb_mapping if defined?(@tsb_mapping)
        return @tsb_mapping = nil if tsb_mapping_offset.zero?

        data = raw_data
        offset = tsb_mapping_offset

        return @tsb_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @tsb_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse VVAR TSB mapping: #{e.message}"
        @tsb_mapping = nil
      end

      # Parse BSB (bottom side bearing) mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] BSB map
      def bsb_mapping
        return @bsb_mapping if defined?(@bsb_mapping)
        return @bsb_mapping = nil if bsb_mapping_offset.zero?

        data = raw_data
        offset = bsb_mapping_offset

        return @bsb_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @bsb_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse VVAR BSB mapping: #{e.message}"
        @bsb_mapping = nil
      end

      # Parse vertical origin mapping
      #
      # @return [VariationCommon::DeltaSetIndexMap, nil] VOrig map
      def v_org_mapping
        return @v_org_mapping if defined?(@v_org_mapping)
        return @v_org_mapping = nil if v_org_mapping_offset.zero?

        data = raw_data
        offset = v_org_mapping_offset

        return @v_org_mapping = nil if offset >= data.bytesize

        map_data = data.byteslice(offset..-1)
        @v_org_mapping = VariationCommon::DeltaSetIndexMap.read(map_data)
      rescue StandardError => e
        warn "Failed to parse VVAR vertical origin mapping: #{e.message}"
        @v_org_mapping = nil
      end

      # Get advance height delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def advance_height_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if advance_height_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = advance_height_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
      end

      # Get TSB delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def tsb_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if tsb_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = tsb_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
      end

      # Get BSB delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def bsb_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if bsb_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = bsb_mapping.map_data
        return nil if glyph_id >= map_data.length

        delta_index = map_data[glyph_id]
        outer_index = (delta_index >> 16) & 0xFFFF
        inner_index = delta_index & 0xFFFF

        item_variation_store.delta_set(outer_index, inner_index)
      end

      # Get vertical origin delta set for a glyph
      #
      # @param glyph_id [Integer] Glyph ID
      # @return [Array<Integer>, nil] Delta values or nil
      def v_org_delta_set(glyph_id)
        return nil unless item_variation_store

        # If no mapping, use glyph_id directly
        if v_org_mapping.nil?
          return item_variation_store.delta_set(0, glyph_id)
        end

        # Use mapping to get delta set indices
        map_data = v_org_mapping.map_data
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
