# frozen_string_literal: true

module Fontisan
  module Collection
    class Reader
      # Snapshot of one face's headline metrics. Pure value object —
      # no methods beyond accessors. Separate file from {Reader} so
      # the Stats struct can be referenced without pulling in the
      # full Reader (and its FontLoader dependency).
      #
      # @!attribute [r] index
      #   @return [Integer] 0-based face index inside the collection
      # @!attribute [r] glyph_count
      #   @return [Integer] face's maxp.numGlyphs
      # @!attribute [r] codepoint_count
      #   @return [Integer] count of keys in face's cmap unicode_mappings
      # @!attribute [r] sfnt_version
      #   @return [Integer] face sfnt version (0x00010000 for TTF, 0x4F54544F for OTF)
      Stats = Struct.new(:index, :glyph_count, :codepoint_count, :sfnt_version,
                         keyword_init: true)
    end
  end
end
