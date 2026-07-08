# frozen_string_literal: true

module Fontisan
  module Tables
    # SbitLineMetrics record embedded in CBLC BitmapSize records.
    #
    # Two of these (horizontal + vertical) appear in every BitmapSize,
    # totalling 24 bytes per strike. The fields are signed/unsigned 8-bit
    # integers; OpenType specifies signed values for some, unsigned for
    # others, mirroring the EBDT/BDF layout.
    #
    # Reference: OpenType CBLC spec, "SbitLineMetrics" sub-structure.
    class CblcSbitLineMetrics < Binary::BaseRecord
      int8 :ascender
      int8 :descender
      uint8 :width_max
      int8 :caret_slope_numerator
      int8 :caret_slope_denominator
      int8 :caret_offset
      int8 :min_origin_sb
      int8 :min_advance_sb
      int8 :max_before_bl
      int8 :min_after_bl
      int8 :pad1
      int8 :pad2
    end
  end
end
