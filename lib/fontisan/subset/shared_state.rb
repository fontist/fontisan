# frozen_string_literal: true

module Fontisan
  module Subset
    # Per-subsetting shared state.
    #
    # Several subset strategies depend on values computed by earlier
    # strategies during the same subsetting run:
    #
    #   - `subset_max_advance` is computed by the Hmtx strategy and read
    #     by Hhea (because hhea is processed alphabetically before hmtx).
    #   - `glyf_data`, `loca_offsets`, and `subset_bbox` are computed by
    #     the Glyf strategy and consumed by Loca and Head.
    #
    # Rather than giving each TableStrategy access to the entire
    # TableSubsetter (which would couple them to internals), the
    # cross-strategy state lives here. Each strategy receives a Context
    # exposing [font], [mapping], [options], and this [SharedState].
    class SharedState
      # @return [String, nil] binary glyf data built by the Glyf strategy
      attr_accessor :glyf_data

      # @return [Array<Integer>, nil] loca offsets produced by the Glyf strategy
      attr_accessor :loca_offsets

      # @return [Array(Integer, Integer, Integer, Integer), nil] union
      #   xMin/yMin/xMax/yMax over the subset's glyphs
      attr_accessor :subset_bbox

      # @return [Integer] largest advanceWidth seen while subsetting hmtx
      attr_accessor :subset_max_advance

      # @return [TableStrategy::ColorBitmapSubsetter, nil] cached paired
      #   CBDT+CBLC subsetter so both strategies reuse the same pass
      attr_accessor :color_bitmap_subsetter

      def initialize
        @subset_max_advance = 0
      end
    end
  end
end
