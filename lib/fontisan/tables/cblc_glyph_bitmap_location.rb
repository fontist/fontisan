# frozen_string_literal: true

module Fontisan
  module Tables
    # Immutable value object locating one glyph's bitmap inside a CBDT table.
    #
    # A CblcIndexSubTable produces one of these per glyph in its range.
    # The subsetting pipeline reads them to know which CBDT byte range to
    # retain, then computes fresh offsets for the subset output.
    #
    # @!attribute glyph_id
    #   @return [Integer] source glyph ID
    # @!attribute image_format
    #   @return [Integer] CBDT image format (e.g. 17, 18, 19)
    # @!attribute cbdt_offset
    #   @return [Integer] absolute byte offset within the source CBDT
    # @!attribute byte_length
    #   @return [Integer] length of the bitmap block in CBDT
    CblcGlyphBitmapLocation = Struct.new(:glyph_id, :image_format,
                                         :cbdt_offset, :byte_length,
                                         keyword_init: true) do
      def initialize(*)
        super
        freeze
      end
    end
  end
end
