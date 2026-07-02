# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `meta` table.
      #
      # The meta table stores font metadata as tagged data — longer-form
      # strings than the `name` table supports. Common tags:
      #   "dlng" — design languages (BCP-47 tags)
      #   "slng" — supported languages
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/meta
      module Meta
        VERSION = 1
        HEADER_SIZE = 16
        DATA_MAP_SIZE = 12 # tag(4) + offset(4) + length(4)

        # @param data [Hash<String,String>] tag → UTF-8 string value
        # @return [String, nil] meta table bytes, or nil if no data
        def self.build(data:)
          return nil if data.nil? || data.empty?

          count = data.size
          data_offset = HEADER_SIZE + (count * DATA_MAP_SIZE)

          header = [VERSION, 0, count, data_offset].pack("NNNN")

          map_entries = +""
          values = +""
          offset = data_offset
          data.each do |tag, value|
            map_entries << tag.ljust(4, " ")[0, 4]
            map_entries << [offset, value.bytesize].pack("NN")
            offset += value.bytesize
            values << value.b
          end

          header + map_entries + values
        end
      end
    end
  end
end
