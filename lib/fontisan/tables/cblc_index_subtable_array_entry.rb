# frozen_string_literal: true

module Fontisan
  module Tables
    # Entry in a CBLC IndexSubTableArray (8 bytes).
    #
    # The IndexSubTableArray sits at `BitmapSize#index_subtable_array_offset`
    # (relative to the start of CBLC) and contains `number_of_index_subtables`
    # of these entries. Each entry points (via `additional_offset_to_index_subtable`,
    # relative to the IndexSubTableArray's own location) at an IndexSubTable
    # record describing how to find the bitmaps for a glyph range.
    #
    # Reference: OpenType CBLC spec, IndexSubTableArray record.
    class CblcIndexSubTableArrayEntry < Binary::BaseRecord
      uint16 :first_glyph_index
      uint16 :last_glyph_index
      uint32 :additional_offset_to_index_subtable
    end
  end
end
