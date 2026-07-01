# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff2
      # The CFF2 table header: 5 bytes at the start of every CFF2 table.
      #
      #   majorVersion  (uint8) = 2
      #   minorVersion  (uint8) = 0
      #   headerSize    (uint8) = 5
      #   topDictSize   (uint16) length of the TopDICT that follows
      #
      # The TopDICT starts immediately after the header (at offset 5).
      # The GlobalSubrINDEX starts at headerSize + topDictSize.
      module Header
        MAJOR_VERSION = 2
        MINOR_VERSION = 0
        HEADER_SIZE = 5
        BYTESIZE = 5

        # @param top_dict_size [Integer] length of the TopDICT subtable
        # @return [String] 5-byte header
        def self.build(top_dict_size:)
          [
            MAJOR_VERSION,
            MINOR_VERSION,
            HEADER_SIZE,
            top_dict_size,
          ].pack("CCCn")
        end
      end
    end
  end
end
