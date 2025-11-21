# frozen_string_literal: true

require_relative "../binary/base_record"
require_relative "variation_common"

module Fontisan
  module Tables
    # Parser for the 'MVAR' (Metrics Variations) table
    #
    # The MVAR table provides variation data for global font metrics such as:
    # - Ascender and descender
    # - Line gap
    # - Caret offsets
    # - Strikeout and underline positions/sizes
    # - Subscript and superscript sizes
    #
    # Each metric is identified by a tag and references delta sets in the
    # ItemVariationStore.
    #
    # Reference: OpenType specification, MVAR table
    #
    # @example Reading an MVAR table
    #   data = font.table_data("MVAR")
    #   mvar = Fontisan::Tables::Mvar.read(data)
    #   hasc_deltas = mvar.metric_deltas("hasc")
    class Mvar < Binary::BaseRecord
      uint16 :major_version
      uint16 :minor_version
      uint16 :reserved
      uint16 :value_record_size
      uint16 :value_record_count
      uint32 :item_variation_store_offset

      # Value tags for standard metrics
      METRIC_TAGS = {
        "hasc" => :horizontal_ascender,
        "hdsc" => :horizontal_descender,
        "hlgp" => :horizontal_line_gap,
        "hcla" => :horizontal_caret_ascender,
        "hcld" => :horizontal_caret_descender,
        "hcof" => :horizontal_caret_offset,
        "vasc" => :vertical_ascender,
        "vdsc" => :vertical_descender,
        "vlgp" => :vertical_line_gap,
        "vcof" => :vertical_caret_offset,
        "xhgt" => :x_height,
        "cpht" => :cap_height,
        "sbxs" => :subscript_em_x_size,
        "sbys" => :subscript_em_y_size,
        "sbxo" => :subscript_em_x_offset,
        "sbyo" => :subscript_em_y_offset,
        "spxs" => :superscript_em_x_size,
        "spys" => :superscript_em_y_size,
        "spxo" => :superscript_em_x_offset,
        "spyo" => :superscript_em_y_offset,
        "strs" => :strikeout_size,
        "stro" => :strikeout_offset,
        "unds" => :underline_size,
        "undo" => :underline_offset,
      }.freeze

      # Value record structure
      class ValueRecord < Binary::BaseRecord
        string :value_tag, length: 4
        uint32 :delta_set_outer_index
        uint32 :delta_set_inner_index

        # Get the metric name for this value tag
        #
        # @return [Symbol, nil] Metric name or nil
        def metric_name
          METRIC_TAGS[value_tag]
        end
      end

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
        warn "Failed to parse MVAR item variation store: #{e.message}"
        @item_variation_store = nil
      end

      # Parse value records
      #
      # @return [Array<ValueRecord>] Value records
      def value_records
        return @value_records if @value_records
        return @value_records = [] if value_record_count.zero?

        data = raw_data
        # Value records start after the header (14 bytes: 2+2+2+2+2+4)
        offset = 14

        @value_records = Array.new(value_record_count) do |i|
          record_offset = offset + (i * value_record_size)

          next nil if record_offset + value_record_size > data.bytesize

          record_data = data.byteslice(record_offset, value_record_size)
          ValueRecord.read(record_data)
        end.compact
      end

      # Get value record by tag
      #
      # @param tag [String] Value tag (e.g., "hasc", "hdsc")
      # @return [ValueRecord, nil] Value record or nil
      def value_record(tag)
        value_records.find { |record| record.value_tag.to_s == tag }
      end

      # Get delta set for a specific metric tag
      #
      # @param tag [String] Value tag (e.g., "hasc", "hdsc")
      # @return [Array<Integer>, nil] Delta values or nil
      def metric_delta_set(tag)
        return nil unless item_variation_store

        record = value_record(tag)
        return nil if record.nil?

        item_variation_store.delta_set(
          record.delta_set_outer_index,
          record.delta_set_inner_index,
        )
      end

      # Get all metric tags present in this table
      #
      # @return [Array<String>] Array of metric tags
      def metric_tags
        value_records.map { |record| record.value_tag.to_s }
      end

      # Get all metrics as a hash
      #
      # @return [Hash<String, Hash>] Hash of metric tag to record info
      def metrics
        value_records.each_with_object({}) do |record, hash|
          # Strip trailing nulls from value_tag
          tag = record.value_tag.delete("\x00")
          hash[tag] = {
            name: record.metric_name,
            outer_index: record.delta_set_outer_index,
            inner_index: record.delta_set_inner_index,
          }
        end
      end

      # Check if a specific metric is present
      #
      # @param tag [String] Value tag
      # @return [Boolean] True if metric is present
      def has_metric?(tag)
        !value_record(tag).nil?
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
