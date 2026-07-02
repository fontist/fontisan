# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `COLR` (Color) table (version 0).
      #
      # COLR v0 maps glyph IDs to layers. Each layer is a reference
      # to another glyph painted in a specific color. This produces
      # multi-color glyphs (e.g., emoji) using simple flat layers.
      #
      # For the more complex paint graph (gradients, affine transforms),
      # use COLRv1 (TODO 10 — not yet implemented).
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/colr
      module Colr
        VERSION = 0
        HEADER_SIZE = 14
        BASE_GLYPH_RECORD_SIZE = 6
        LAYER_RECORD_SIZE = 4

        # @param layers [Array<Hash>] each with :gid (Integer),
        #   :palette_index (Integer), :layer_gid (Integer)
        # @return [String, nil] COLR table bytes, or nil if no layers
        def self.build(layers:)
          return nil if layers.nil? || layers.empty?

          groups = layers.group_by { |l| l[:gid] }

          base_records = +""
          layer_records = +""
          num_layers_total = 0

          groups.keys.sort.each do |gid|
            group_layers = groups[gid].sort_by { |l| l[:palette_index] || 0 }
            num_layers_total += group_layers.size
            base_records << [gid, num_layers_total, num_layers_total - group_layers.size].pack("nCC")

            groups[gid].sort_by { |l| l[:palette_index] || 0 }.each do |l|
              layer_records << [l[:layer_gid] || 0, l[:palette_index] || 0].pack("nC")
            end
          end

          layer_offset = HEADER_SIZE + (groups.size * BASE_GLYPH_RECORD_SIZE)

          io = +""
          io << [VERSION, 0, groups.size, layer_offset, num_layers_total].pack("nnnnn")
          io << base_records
          io << layer_records
          io
        end
      end
    end
  end
end
