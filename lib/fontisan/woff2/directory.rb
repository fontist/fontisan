# frozen_string_literal: true

module Fontisan
  module Woff2
    # WOFF2 Table Directory Entry
    #
    # [`Woff2::Directory`](lib/fontisan/woff2/directory.rb) represents
    # a single table entry in the WOFF2 table directory. Unlike WOFF,
    # WOFF2 uses variable-length encoding for sizes and supports table
    # transformations for better compression.
    #
    # Each entry contains:
    # - flags (1 byte): Contains tag index and transformation version
    # - tag (0 or 4 bytes): Table tag (omitted if using known tag index)
    # - origLength (UIntBase128): Original uncompressed table length
    # - transformLength (UIntBase128, optional): Transformed data length
    #
    # Flags byte structure:
    # - Bits 0-5: Table tag index (0-62 = known tags, 63 = custom tag)
    # - Bits 6-7: Transformation version
    #
    # Reference: https://www.w3.org/TR/WOFF2/#table_dir_format
    #
    # @example Create entry for known table
    #   entry = Directory::Entry.new
    #   entry.tag = "glyf"
    #   entry.orig_length = 12000
    #   entry.flags = entry.calculate_flags
    #
    # @example Create entry for custom table
    #   entry = Directory::Entry.new
    #   entry.tag = "CUST"
    #   entry.orig_length = 5000
    #   entry.flags = 0x3F # Custom tag indicator
    module Directory
      # Known table tags with assigned indices (0-62)
      # Index 63 (0x3F) indicates a custom tag follows
      KNOWN_TAGS = [
        "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post",
        "cvt ", "fpgm", "glyf", "loca", "prep", "CFF ", "VORG", "EBDT",
        "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea",
        "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH",
        "CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt", "avar",
        "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar",
        "gvar", "hsty", "just", "lcar", "mort", "morx", "opbd", "prop",
        "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill"
      ].freeze

      # Transformation versions
      # According to WOFF2 spec:
      # - glyf/loca: version 0 or 3 WITH transformLength = transformed
      # - glyf/loca: version 1 or 2 WITHOUT transformLength = not transformed
      # - hmtx: version 1 WITH transformLength = transformed
      # - hmtx: version 0, 2, or 3 WITHOUT transformLength = not transformed
      TRANSFORM_NONE = 3           # Use version 3 when not transformed (works for all tables)
      TRANSFORM_GLYF_LOCA = 0      # glyf/loca use version 0 when transformed
      TRANSFORM_HMTX = 1           # hmtx uses version 1 when transformed

      # Custom tag indicator
      CUSTOM_TAG_INDEX = 0x3F

      # WOFF2 Table Directory Entry
      #
      # Represents a single table in the WOFF2 font with all metadata
      # needed for decompression and reconstruction.
      class Entry
        attr_accessor :tag, :flags, :orig_length, :transform_length, :offset # Calculated during encoding

        def initialize
          @tag = nil
          @flags = 0
          @orig_length = 0
          @transform_length = nil
          @offset = 0
        end

        # Calculate flags byte for this entry
        #
        # @return [Integer] Flags byte (0-255)
        def calculate_flags
          tag_index = KNOWN_TAGS.index(tag) || CUSTOM_TAG_INDEX
          transform_version = determine_transform_version

          # Combine tag index (bits 0-5) and transform version (bits 6-7)
          (transform_version << 6) | tag_index
        end

        # Check if table uses a known tag
        #
        # @return [Boolean] True if known tag
        def known_tag?
          KNOWN_TAGS.include?(tag)
        end

        # Check if table is transformed
        #
        # @return [Boolean] True if transformed
        def transformed?
          !transform_length.nil? && transform_length.positive?
        end

        # Get transformation version from flags
        #
        # @return [Integer] Transform version (0-3)
        def transform_version
          (flags >> 6) & 0x03
        end

        # Get tag index from flags
        #
        # @return [Integer] Tag index (0-63)
        def tag_index
          flags & 0x3F
        end

        # Determine transformation version for this table
        #
        # Returns the appropriate version based on:
        # 1. Whether table has transform_length set (is transformed)
        # 2. Which table it is (glyf/loca vs hmtx vs other)
        #
        # @return [Integer] Transform version (0-3)
        def determine_transform_version
          if transformed?
            # Table IS transformed - use appropriate transform version
            case tag
            when "glyf", "loca"
              TRANSFORM_GLYF_LOCA  # Version 0 for transformed glyf/loca
            when "hmtx"
              TRANSFORM_HMTX       # Version 1 for transformed hmtx
            else
              TRANSFORM_NONE       # Shouldn't happen, but use safe default
            end
          else
            # Table is NOT transformed - use version that indicates no transformation
            case tag
            when "glyf", "loca"
              # For glyf/loca, version 0 means transformed
              # so use version 3 to indicate NOT transformed
              TRANSFORM_NONE # Version 3
            when "hmtx"
              # For hmtx, version 1 means transformed
              # so use version 0 to indicate NOT transformed
              0
            else
              # All other tables use version 0 (no transformation)
              0
            end
          end
        end

        # Check if table can be transformed (glyf, loca, hmtx)
        #
        # @return [Boolean] True if transformable
        def transformable?
          %w[glyf loca hmtx].include?(tag)
        end

        # Calculate size of this entry when serialized
        #
        # @return [Integer] Size in bytes
        def serialized_size
          size = 1 # flags byte
          size += 4 unless known_tag? # custom tag
          size += uint_base128_size(orig_length)
          size += uint_base128_size(transform_length) if transformed?
          size
        end

        private

        # Estimate size of UIntBase128 encoded value
        #
        # @param value [Integer] Value to encode
        # @return [Integer] Size in bytes (1-5)
        def uint_base128_size(value)
          return 1 if value.nil? || value < 128

          bytes = 0
          v = value
          while v.positive?
            bytes += 1
            v >>= 7
          end
          [bytes, 5].min # Max 5 bytes
        end
      end

      # Encode an integer as UIntBase128
      #
      # Variable-length encoding where:
      # - If value < 128, use 1 byte
      # - Otherwise, use high bit to indicate continuation
      #
      # @param value [Integer] Value to encode
      # @return [String] Binary encoded data
      def self.encode_uint_base128(value)
        return [value].pack("C") if value < 128

        bytes = []
        v = value

        # Build bytes from least to most significant
        loop do
          bytes.unshift(v & 0x7F)
          v >>= 7
          break if v.zero?
        end

        # Set high bit on all but last byte
        (0...bytes.length - 1).each do |i|
          bytes[i] |= 0x80
        end

        bytes.pack("C*")
      end

      # Decode UIntBase128 from IO
      #
      # @param io [IO] Input stream
      # @return [Integer] Decoded value
      # @raise [Error] If encoding is invalid
      def self.decode_uint_base128(io)
        result = 0
        5.times do
          byte = io.read(1)&.unpack1("C")
          return nil unless byte

          # Check if high bit is set (continuation)
          if (byte & 0x80).zero?
            return (result << 7) | byte
          else
            result = (result << 7) | (byte & 0x7F)
          end
        end

        # If we're here, encoding is invalid (> 5 bytes)
        raise Fontisan::Error, "Invalid UIntBase128 encoding"
      end

      # Encode 255UInt16 value
      #
      # Used in transformed glyf table:
      # - 0-252: value itself (1 byte)
      # - 253: next byte + 253 (2 bytes)
      # - 254: next 2 bytes as big-endian (3 bytes)
      # - 255: next 2 bytes + 506 (3 bytes)
      #
      # @param value [Integer] Value to encode (0-65535)
      # @return [String] Binary encoded data
      def self.encode_255_uint16(value)
        if value < 253
          [value].pack("C")
        elsif value < 506
          [253, value - 253].pack("C*")
        elsif value < 65536
          [254].pack("C") + [value].pack("n")
        else
          [255].pack("C") + [value - 506].pack("n")
        end
      end

      # Decode 255UInt16 from IO
      #
      # @param io [IO] Input stream
      # @return [Integer] Decoded value
      def self.decode_255_uint16(io)
        first = io.read(1)&.unpack1("C")
        return nil unless first

        case first
        when 0..252
          first
        when 253
          second = io.read(1)&.unpack1("C")
          253 + second
        when 254
          io.read(2)&.unpack1("n")
        when 255
          value = io.read(2)&.unpack1("n")
          value + 506
        end
      end
    end
  end
end
