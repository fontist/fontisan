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
      # Header (14 bytes):
      #   uint16 version (= 0)
      #   uint16 numBaseGlyphRecords
      #   Offset32 baseGlyphRecordsOffset
      #   Offset32 layerRecordsOffset
      #   uint16 numLayerRecords
      #
      # BaseGlyphRecord (6 bytes):
      #   uint16 glyphID
      #   uint16 firstLayerIndex
      #   uint16 numLayers
      #
      # LayerRecord (3 bytes):
      #   uint16 layerGlyphID
      #   uint8 paletteIndex
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/colr
      module Colr
        VERSION = 0
        HEADER_SIZE = 14
        BASE_GLYPH_RECORD_SIZE = 6
        LAYER_RECORD_SIZE = 3

        # @param base_glyphs [Array<Hash>] each with :gid (Integer) and
        #   :layers (Array<Hash> with :layer_gid and :palette_index)
        # @return [String, nil] COLR table bytes, or nil if no base glyphs
        def self.build(base_glyphs:)
          return nil if base_glyphs.nil? || base_glyphs.empty?

          base_records = +""
          layer_records = +""
          first_layer_index = 0

          base_glyphs.each do |bg|
            layers = bg[:layers] || []
            num_layers = layers.size

            base_records << [
              bg[:gid] || 0,
              first_layer_index,
              num_layers,
            ].pack("nnn")

            layers.each do |layer|
              layer_records << [
                layer[:layer_gid] || 0,
                layer[:palette_index] || 0,
              ].pack("nC")
            end

            first_layer_index += num_layers
          end

          num_base = base_glyphs.size
          base_offset = HEADER_SIZE
          layer_offset = base_offset + (num_base * BASE_GLYPH_RECORD_SIZE)
          num_layer_records = layer_records.bytesize / LAYER_RECORD_SIZE

          io = +""
          io << [VERSION, num_base, base_offset, layer_offset,
                 num_layer_records].pack("nnNNn")
          io << base_records
          io << layer_records
          io
        end
      end
    end
  end
end
