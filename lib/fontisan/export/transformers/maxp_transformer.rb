# frozen_string_literal: true

require_relative "../../models/ttx/tables/maxp_table"

module Fontisan
  module Export
    module Transformers
      # MaxpTransformer transforms maxp table to TTX format
      #
      # Converts Fontisan maximum profile table to Models::Ttx::Tables::MaxpTable
      # following proper model-to-model transformation principles.
      class MaxpTransformer
        # Transform maxp table to TTX model
        #
        # @param maxp_table [Object] Source maxp table
        # @return [Models::Ttx::Tables::MaxpTable] TTX maxp table model
        def self.transform(maxp_table)
          return nil unless maxp_table

          version = to_int(maxp_table.version)

          Models::Ttx::Tables::MaxpTable.new.tap do |ttx|
            ttx.table_version = format_hex(version)
            ttx.num_glyphs = to_int(maxp_table.num_glyphs)

            # Version 1.0 fields (TrueType)
            if version >= 0x00010000
              ttx.max_points = to_int(maxp_table.max_points)
              ttx.max_contours = to_int(maxp_table.max_contours)
              ttx.max_composite_points = to_int(maxp_table.max_component_points)
              ttx.max_composite_contours = to_int(maxp_table.max_component_contours)
              ttx.max_zones = to_int(maxp_table.max_zones)
              ttx.max_twilight_points = to_int(maxp_table.max_twilight_points)
              ttx.max_storage = to_int(maxp_table.max_storage)
              ttx.max_function_defs = to_int(maxp_table.max_function_defs)
              ttx.max_instruction_defs = to_int(maxp_table.max_instruction_defs)
              ttx.max_stack_elements = to_int(maxp_table.max_stack_elements)
              ttx.max_size_of_instructions = to_int(maxp_table.max_size_of_instructions)
              ttx.max_component_elements = to_int(maxp_table.max_component_elements)
              ttx.max_component_depth = to_int(maxp_table.max_component_depth)
            end
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
