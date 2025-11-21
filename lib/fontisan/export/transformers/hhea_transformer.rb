# frozen_string_literal: true

require_relative "../../models/ttx/tables/hhea_table"

module Fontisan
  module Export
    module Transformers
      # HheaTransformer transforms hhea table to TTX format
      #
      # Converts Fontisan horizontal header table to Models::Ttx::Tables::HheaTable
      # following proper model-to-model transformation principles.
      class HheaTransformer
        # Transform hhea table to TTX model
        #
        # @param hhea_table [Object] Source hhea table
        # @return [Models::Ttx::Tables::HheaTable] TTX hhea table model
        def self.transform(hhea_table)
          return nil unless hhea_table

          Models::Ttx::Tables::HheaTable.new.tap do |ttx|
            ttx.table_version = format_hex(to_int(hhea_table.version_raw))
            ttx.ascent = to_int(hhea_table.ascent)
            ttx.descent = to_int(hhea_table.descent)
            ttx.line_gap = to_int(hhea_table.line_gap)
            ttx.advance_width_max = to_int(hhea_table.advance_width_max)
            ttx.min_left_side_bearing = to_int(hhea_table.min_left_side_bearing)
            ttx.min_right_side_bearing = to_int(hhea_table.min_right_side_bearing)
            ttx.x_max_extent = to_int(hhea_table.x_max_extent)
            ttx.caret_slope_rise = to_int(hhea_table.caret_slope_rise)
            ttx.caret_slope_run = to_int(hhea_table.caret_slope_run)
            ttx.caret_offset = to_int(hhea_table.caret_offset)
            ttx.reserved0 = 0
            ttx.reserved1 = 0
            ttx.reserved2 = 0
            ttx.reserved3 = 0
            ttx.metric_data_format = to_int(hhea_table.metric_data_format)
            ttx.number_of_h_metrics = to_int(hhea_table.number_of_h_metrics)
          end
        end

        # Convert BinData value to native Ruby integer
        #
        # @param value [Object] BinData value or integer
        # @return [Integer] Native integer
        def self.to_int(value)
          value.respond_to?(:to_i) ? value.to_i : value
        end

        # Format hex value
        #
        # @param value [Integer] Integer value
        # @return [String] Hex string (e.g., "0x00010000")
        def self.format_hex(value)
          "0x#{value.to_s(16).rjust(8, '0')}"
        end
      end
    end
  end
end
