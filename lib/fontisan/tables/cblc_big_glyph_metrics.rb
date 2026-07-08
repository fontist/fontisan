# frozen_string_literal: true

module Fontisan
  module Tables
    # 8-byte bigGlyphMetrics record embedded in CBLC IndexSubTable formats
    # 2 and 5 (constant-metrics strikes). Layout is smallGlyphMetrics (5
    # bytes) plus four additional signed advance fields.
    #
    #   uint8 height
    #   uint8 width
    #   int8  bearing_x
    #   int8  bearing_y
    #   int8  advance
    #   int8  reserved
    #   int8  advance_lsb
    #   int8  advance_rsb
    class CblcBigGlyphMetrics < Binary::BaseRecord
      uint8 :height
      uint8 :width
      int8 :bearing_x
      int8 :bearing_y
      int8 :advance
      int8 :reserved
      int8 :advance_lsb
      int8 :advance_rsb
    end
  end
end
