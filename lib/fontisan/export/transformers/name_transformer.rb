# frozen_string_literal: true

require_relative "../../models/ttx/tables/name_table"

module Fontisan
  module Export
    module Transformers
      # NameTransformer transforms name table to TTX format
      #
      # Converts Fontisan::Tables::Name to Models::Ttx::Tables::NameTable
      # following proper model-to-model transformation principles.
      class NameTransformer
        # Transform name table to TTX model
        #
        # @param name_table [Tables::Name] Source name table
        # @return [Models::Ttx::Tables::NameTable] TTX name table model
        def self.transform(name_table)
          return nil unless name_table

          Models::Ttx::Tables::NameTable.new.tap do |ttx|
            ttx.name_records = transform_name_records(name_table.name_records)
          end
        end

        # Transform name records
        #
        # @param records [Array] Name records from source table
        # @return [Array<Models::Ttx::Tables::NameRecord>] TTX name records
        def self.transform_name_records(records)
          return [] unless records

          records.map do |record|
            Models::Ttx::Tables::NameRecord.new.tap do |ttx_record|
              ttx_record.name_id = to_int(record.name_id)
              ttx_record.platform_id = to_int(record.platform_id)
              ttx_record.plat_enc_id = to_int(record.encoding_id)
              ttx_record.lang_id = format_hex(to_int(record.language_id),
                                              width: 3)
              ttx_record.string = record.string
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
        # @param width [Integer] Minimum hex width
        # @return [String] Hex string (e.g., "0x1234")
        def self.format_hex(value, width: 8)
          "0x#{value.to_s(16).rjust(width, '0')}"
        end
      end
    end
  end
end
