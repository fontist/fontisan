# frozen_string_literal: true

module Fontisan
  module Tables
    # 8-byte header common to all CBLC IndexSubTable formats.
    #
    #   uint16 indexFormat
    #   uint16 imageFormat
    #   uint32 imageDataOffset (absolute, from start of CBDT)
    #
    # Format-specific data follows immediately after this header.
    class CblcIndexSubTableHeader < Binary::BaseRecord
      uint16 :index_format
      uint16 :image_format
      uint32 :image_data_offset
    end
  end
end
