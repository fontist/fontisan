# frozen_string_literal: true

require "bindata"

module Fontisan
  module Woff2
    # WOFF2 Header structure
    #
    # [`Woff2::Header`](lib/fontisan/woff2/header.rb) represents the main
    # header of a WOFF2 file according to W3C WOFF2 specification.
    #
    # The header is more compact than WOFF, using 48 bytes.
    #
    # Structure (all big-endian):
    # - uint32: signature (0x774F4632 'wOF2')
    # - uint32: flavor (0x00010000 for TTF, 0x4F54544F for CFF)
    # - uint32: file_length (total WOFF2 file size)
    # - uint16: numTables (number of font tables)
    # - uint16: reserved (must be 0)
    # - uint32: totalSfntSize (uncompressed font size)
    # - uint32: totalCompressedSize (size of compressed data block)
    # - uint16: majorVersion (major version of WOFF file)
    # - uint16: minorVersion (minor version of WOFF file)
    # - uint32: metaOffset (offset to metadata, 0 if none)
    # - uint32: metaLength (compressed metadata length)
    # - uint32: metaOrigLength (uncompressed metadata length)
    # - uint32: privOffset (offset to private data, 0 if none)
    # - uint32: privLength (length of private data)
    #
    # Reference: https://www.w3.org/TR/WOFF2/#woff20Header
    #
    # @example Create a header
    #   header = Woff2::Header.new
    #   header.signature = 0x774F4632
    #   header.flavor = 0x00010000
    #   header.num_tables = 10
    class Woff2Header < BinData::Record
      endian :big

      uint32 :signature         # 'wOF2' magic number
      uint32 :flavor            # Font format (TTF or CFF)
      uint32 :file_length       # Total WOFF2 file size
      uint16 :num_tables        # Number of font tables
      uint16 :reserved          # Reserved, must be 0
      uint32 :total_sfnt_size   # Uncompressed font size
      uint32 :total_compressed_size # Compressed data block size
      uint16 :major_version     # Major version number
      uint16 :minor_version     # Minor version number
      uint32 :meta_offset       # Metadata block offset (0 if none)
      uint32 :meta_length       # Compressed metadata length
      uint32 :meta_orig_length  # Uncompressed metadata length
      uint32 :priv_offset       # Private data offset (0 if none)
      uint32 :priv_length       # Private data length

      # WOFF2 signature constant
      SIGNATURE = 0x774F4632 # 'wOF2'

      # Check if signature is valid
      #
      # @return [Boolean] True if signature is valid
      def valid_signature?
        signature == SIGNATURE
      end

      # Check if font is TrueType flavored
      #
      # @return [Boolean] True if TrueType
      def truetype?
        [0x00010000, 0x74727565].include?(flavor) # 'true'
      end

      # Check if font is CFF flavored
      #
      # @return [Boolean] True if CFF/OpenType
      def cff?
        flavor == 0x4F54544F # 'OTTO'
      end

      # Check if metadata is present
      #
      # @return [Boolean] True if metadata exists
      def has_metadata?
        meta_offset.positive? && meta_length.positive?
      end

      # Check if private data is present
      #
      # @return [Boolean] True if private data exists
      def has_private_data?
        priv_offset.positive? && priv_length.positive?
      end

      # Get header size in bytes
      #
      # @return [Integer] Header size (always 48 bytes)
      def self.header_size
        48
      end
    end
  end
end
