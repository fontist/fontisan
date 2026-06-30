# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `HVAR` (Horizontal Metrics Variation) table.
      #
      # Stores advance-width variation deltas per glyph, enabling
      # variable-font renderers to adjust spacing without loading gvar.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/HVAR
      module Hvar
        # @param default_widths [Array<Integer>] advance widths for default master
        # @param master_widths [Array<Array<Integer>>] advance widths per master
        # @param axis_count [Integer]
        # @return [String] HVAR table bytes
        def self.build(default_widths:, master_widths:, axis_count:)
          glyph_count = default_widths.size
          master_count = master_widths.size

          # Compute deltas: deltas[glyph][master] = master_width - default_width
          deltas = Array.new(glyph_count) do |gid|
            Array.new(master_count) do |mid|
              master_widths.dig(mid, gid).to_i - default_widths[gid].to_i
            end
          end

          store = ItemVariationStore.build(
            axis_count: axis_count,
            master_count: master_count,
            item_count: glyph_count,
            deltas: deltas,
          )

          # HVAR header: version(4) + itemVariationStoreOffset(4) +
          # advanceWidthMappingOffset(4) + lsbMappingOffset(4) + rsbMappingOffset(4)
          [0x00010000, 20].pack("NN") + [0, 0, 0].pack("NNN") + store
        end
      end
    end
  end
end
