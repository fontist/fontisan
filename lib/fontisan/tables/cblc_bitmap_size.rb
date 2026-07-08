# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    # BitmapSize record embedded in a CBLC table (48 bytes).
    #
    # Each BitmapSize describes one bitmap strike: a glyph range rendered
    # at a specific ppem with a specific bit depth. It points (via
    # `index_subtable_array_offset`) at a sequence of IndexSubTableArray
    # records that further describe how to find the bitmap data for each
    # glyph in CBDT.
    #
    # Layout (48 bytes):
    #   uint32 index_subtable_array_offset
    #   uint32 index_tables_size
    #   uint32 number_of_index_subtables
    #   uint32 color_ref
    #   CblcSbitLineMetrics hori (12 bytes)
    #   CblcSbitLineMetrics vert (12 bytes)
    #   uint16 start_glyph_index
    #   uint16 end_glyph_index
    #   uint8  ppem_x
    #   uint8  ppem_y
    #   uint8  bit_depth
    #   int8   flags
    #
    # Reference: OpenType CBLC spec, "BitmapSize" record.
    class CblcBitmapSize < Binary::BaseRecord
      uint32 :index_subtable_array_offset
      uint32 :index_tables_size
      uint32 :number_of_index_subtables
      uint32 :color_ref
      CblcSbitLineMetrics :hori, type: Fontisan::Tables::CblcSbitLineMetrics
      CblcSbitLineMetrics :vert, type: Fontisan::Tables::CblcSbitLineMetrics
      uint16 :start_glyph_index
      uint16 :end_glyph_index
      uint8 :ppem_x
      uint8 :ppem_y
      uint8 :bit_depth
      int8 :flags

      # Pixels per em, assuming square pixels (the common case).
      #
      # @return [Integer] ppem value
      def ppem
        ppem_x
      end

      # Glyph ID range covered by this strike.
      #
      # @return [Range<Integer>] inclusive glyph ID range
      def glyph_range
        start_glyph_index..end_glyph_index
      end

      # Whether the strike covers a specific glyph.
      #
      # @param glyph_id [Integer] source glyph ID
      # @return [Boolean]
      def includes_glyph?(glyph_id)
        glyph_range.include?(glyph_id)
      end
    end
  end
end
