# frozen_string_literal: true

require_relative "../../models/ttx/tables/head_table"

module Fontisan
  module Export
    module Transformers
      # HeadTransformer transforms head table to TTX format
      #
      # Converts Fontisan::Tables::Head to Models::Ttx::Tables::HeadTable
      # following proper model-to-model transformation principles.
      class HeadTransformer
        # Transform head table to TTX model
        #
        # @param head_table [Tables::Head] Source head table
        # @return [Models::Ttx::Tables::HeadTable] TTX head table model
        def self.transform(head_table)
          return nil unless head_table

          Models::Ttx::Tables::HeadTable.new.tap do |ttx|
            ttx.table_version = format_fixed(to_int(head_table.version))
            ttx.font_revision = format_fixed(to_int(head_table.font_revision))
            ttx.checksum_adjustment = format_hex(to_int(head_table.checksum_adjustment))
            ttx.magic_number = format_hex(to_int(head_table.magic_number))
            ttx.flags = to_int(head_table.flags).to_s
            ttx.units_per_em = to_int(head_table.units_per_em).to_s
            ttx.created = format_timestamp(to_int(head_table.created))
            ttx.modified = format_timestamp(to_int(head_table.modified))
            ttx.x_min = to_int(head_table.x_min).to_s
            ttx.y_min = to_int(head_table.y_min).to_s
            ttx.x_max = to_int(head_table.x_max).to_s
            ttx.y_max = to_int(head_table.y_max).to_s
            ttx.mac_style = format_binary_flags(to_int(head_table.mac_style),
                                                16)
            ttx.lowest_rec_ppem = to_int(head_table.lowest_rec_ppem).to_s
            ttx.font_direction_hint = to_int(head_table.font_direction_hint).to_s
            ttx.index_to_loc_format = to_int(head_table.index_to_loc_format).to_s
            ttx.glyph_data_format = to_int(head_table.glyph_data_format).to_s
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
        # @return [String] Decimal string
        def self.format_fixed(value)
          result = value.to_f / 65536.0
          if result == result.to_i
            "#{result.to_i}.0"
          else
            result.to_s
          end
        end

        # Format hex value
        #
        # @param value [Integer] Integer value
        # @param width [Integer] Minimum hex width
        # @return [String] Hex string (e.g., "0x1234")
        def self.format_hex(value, width: 8)
          "0x#{value.to_s(16).rjust(width, '0')}"
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

        # Format timestamp
        #
        # @param timestamp [Integer] Mac timestamp (seconds since 1904-01-01)
        # @return [String] Human-readable date string
        def self.format_timestamp(timestamp)
          mac_epoch = Time.utc(1904, 1, 1)
          time = mac_epoch + timestamp
          time.strftime("%a %b %e %H:%M:%S %Y")
        rescue StandardError
          "Invalid Date"
        end
      end
    end
  end
end
