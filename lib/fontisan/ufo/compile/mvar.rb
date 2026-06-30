# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `MVAR` (Metrics Variation) table.
      #
      # Stores deltas for font-wide metrics (ascender, descender, etc.)
      # so they can vary across the design space.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/MVAR
      module Mvar
        HEADER_SIZE = 10 # majorVersion(2) + minorVersion(2) + valueRecordSize(2) +
        #                valueRecordCount(2) + itemVariationStoreOffset(2)
        VALUE_RECORD_SIZE = 8 # tag(4) + outerIndex(2) + innerIndex(2)

        # @param default_metrics [Hash<Symbol, Integer>] e.g. { hasc: 800, hdsc: -200 }
        # @param master_metrics [Array<Hash<Symbol, Integer>>] per master
        # @param axis_count [Integer]
        # @return [String] MVAR table bytes
        def self.build(default_metrics:, master_metrics:, axis_count:)
          tags = default_metrics.keys
          return nil if tags.empty?

          master_count = master_metrics.size

          deltas = []
          records = +""
          tags.each_with_index do |tag, idx|
            tag_bytes = tag.to_s.ljust(4, " ")[0, 4]
            delta = master_metrics.dig(0, tag).to_i - default_metrics[tag].to_i
            records << tag_bytes
            records << [0, idx].pack("nn") # outerIndex=0, innerIndex=idx
            deltas << [delta]
          end

          store = ItemVariationStore.build(
            axis_count: axis_count,
            master_count: master_count,
            item_count: tags.size,
            deltas: deltas,
          )

          store_offset = HEADER_SIZE + records.bytesize

          io = +""
          io << [1].pack("n")                # majorVersion
          io << [0].pack("n")                # minorVersion
          io << [VALUE_RECORD_SIZE].pack("n")
          io << [tags.size].pack("n")        # valueRecordCount
          io << [store_offset].pack("n")     # itemVariationStoreOffset (Offset16)
          io << records
          io << store
          io
        end
      end
    end
  end
end
