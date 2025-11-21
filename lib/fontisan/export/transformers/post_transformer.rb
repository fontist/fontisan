# frozen_string_literal: true

require_relative "../../models/ttx/tables/post_table"

module Fontisan
  module Export
    module Transformers
      # PostTransformer transforms post table to TTX format
      #
      # Converts Fontisan::Tables::Post to Models::Ttx::Tables::PostTable
      # following proper model-to-model transformation principles.
      class PostTransformer
        # Transform post table to TTX model
        #
        # @param post_table [Tables::Post] Source post table
        # @return [Models::Ttx::Tables::PostTable] TTX post table model
        def self.transform(post_table)
          return nil unless post_table

          Models::Ttx::Tables::PostTable.new.tap do |ttx|
            ttx.format_type = format_fixed(to_int(post_table.version_raw))
            ttx.italic_angle = format_fixed(to_int(post_table.italic_angle_raw))
            ttx.underline_position = to_int(post_table.underline_position)
            ttx.underline_thickness = to_int(post_table.underline_thickness)
            ttx.is_fixed_pitch = to_int(post_table.is_fixed_pitch)
            ttx.min_mem_type42 = to_int(post_table.min_mem_type42)
            ttx.max_mem_type42 = to_int(post_table.max_mem_type42)
            ttx.min_mem_type1 = to_int(post_table.min_mem_type1)
            ttx.max_mem_type1 = to_int(post_table.max_mem_type1)
          end
        end

        # Convert BinData value to native Ruby integer
        #
        # @param value [Object] BinData value or integer
        # @return [Integer] Native integer
        def self.to_int(value)
          value.respond_to?(:to_i) ? value.to_i : value
        end

        # Format fixed-point number (16.16)
        #
        # @param value [Integer] Fixed-point value
        # @return [Float] Decimal value
        def self.format_fixed(value)
          value.to_f / 65536.0
        end
      end
    end
  end
end
