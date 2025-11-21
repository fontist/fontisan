# frozen_string_literal: true

require_relative "../../models/ttx/tables/os2_table"

module Fontisan
  module Export
    module Transformers
      # Os2Transformer transforms OS/2 table to TTX format
      #
      # Converts Fontisan::Tables::Os2 to Models::Ttx::Tables::Os2Table
      # following proper model-to-model transformation principles.
      class Os2Transformer
        # Transform OS/2 table to TTX model
        #
        # @param os2_table [Tables::Os2] Source OS/2 table
        # @return [Models::Ttx::Tables::Os2Table] TTX OS/2 table model
        def self.transform(os2_table)
          return nil unless os2_table

          version = to_int(os2_table.version)

          Models::Ttx::Tables::Os2Table.new.tap do |ttx|
            ttx.version = version
            ttx.x_avg_char_width = to_int(os2_table.x_avg_char_width)
            ttx.us_weight_class = to_int(os2_table.us_weight_class)
            ttx.us_width_class = to_int(os2_table.us_width_class)
            ttx.fs_type = format_binary_flags(to_int(os2_table.fs_type), 16)
            ttx.y_subscript_x_size = to_int(os2_table.y_subscript_x_size)
            ttx.y_subscript_y_size = to_int(os2_table.y_subscript_y_size)
            ttx.y_subscript_x_offset = to_int(os2_table.y_subscript_x_offset)
            ttx.y_subscript_y_offset = to_int(os2_table.y_subscript_y_offset)
            ttx.y_superscript_x_size = to_int(os2_table.y_superscript_x_size)
            ttx.y_superscript_y_size = to_int(os2_table.y_superscript_y_size)
            ttx.y_superscript_x_offset = to_int(os2_table.y_superscript_x_offset)
            ttx.y_superscript_y_offset = to_int(os2_table.y_superscript_y_offset)
            ttx.y_strikeout_size = to_int(os2_table.y_strikeout_size)
            ttx.y_strikeout_position = to_int(os2_table.y_strikeout_position)
            ttx.s_family_class = to_int(os2_table.s_family_class)
            ttx.panose = transform_panose(os2_table.panose)
            ttx.ul_unicode_range_1 = format_binary_flags(
              to_int(os2_table.ul_unicode_range1), 32
            )
            ttx.ul_unicode_range_2 = format_binary_flags(
              to_int(os2_table.ul_unicode_range2), 32
            )
            ttx.ul_unicode_range_3 = format_binary_flags(
              to_int(os2_table.ul_unicode_range3), 32
            )
            ttx.ul_unicode_range_4 = format_binary_flags(
              to_int(os2_table.ul_unicode_range4), 32
            )
            ttx.ach_vend_id = os2_table.vendor_id.to_s.strip
            ttx.fs_selection = format_binary_flags(
              to_int(os2_table.fs_selection), 16
            )
            ttx.us_first_char_index = to_int(os2_table.us_first_char_index)
            ttx.us_last_char_index = to_int(os2_table.us_last_char_index)

            if version >= 1
              ttx.s_typo_ascender = to_int(os2_table.s_typo_ascender)
              ttx.s_typo_descender = to_int(os2_table.s_typo_descender)
              ttx.s_typo_line_gap = to_int(os2_table.s_typo_line_gap)
              ttx.us_win_ascent = to_int(os2_table.us_win_ascent)
              ttx.us_win_descent = to_int(os2_table.us_win_descent)
            end

            if version >= 2
              ttx.ul_code_page_range_1 = format_binary_flags(
                to_int(os2_table.ul_code_page_range1), 32
              )
              ttx.ul_code_page_range_2 = format_binary_flags(
                to_int(os2_table.ul_code_page_range2), 32
              )
            end
          end
        end

        # Transform Panose data
        #
        # @param panose [Object] Panose data (String or Array)
        # @return [Models::Ttx::Tables::Panose] TTX Panose model
        def self.transform_panose(panose)
          return nil unless panose

          bytes = panose.is_a?(String) ? panose.bytes : panose.to_a

          Models::Ttx::Tables::Panose.new.tap do |ttx_panose|
            ttx_panose.b_family_type = bytes[0]
            ttx_panose.b_serif_style = bytes[1]
            ttx_panose.b_weight = bytes[2]
            ttx_panose.b_proportion = bytes[3]
            ttx_panose.b_contrast = bytes[4]
            ttx_panose.b_stroke_variation = bytes[5]
            ttx_panose.b_arm_style = bytes[6]
            ttx_panose.b_letter_form = bytes[7]
            ttx_panose.b_midline = bytes[8]
            ttx_panose.b_x_height = bytes[9]
          end
        end

        # Convert BinData value to native Ruby integer
        #
        # @param value [Object] BinData value or integer
        # @return [Integer] Native integer
        def self.to_int(value)
          value.respond_to?(:to_i) ? value.to_i : value
        end

        # Format binary flags
        #
        # @param value [Integer] Integer value
        # @param bits [Integer] Number of bits
        # @return [String] Binary string with spaces every 8 bits
        def self.format_binary_flags(value, bits)
          binary = value.to_s(2).rjust(bits, "0")
          binary.scan(/.{1,8}/).join(" ")
        end
      end
    end
  end
end
