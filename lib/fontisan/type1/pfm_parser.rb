# frozen_string_literal: true

module Fontisan
  module Type1
    # PFM (Printer Font Metrics) file parser
    #
    # [`PFMParser`](lib/fontisan/type1/pfm_parser.rb) parses Printer Font Metrics
    # files which contain font metric information for Type 1 fonts on Windows.
    #
    # PFM files are binary files that include:
    # - Character widths
    # - Kerning pairs
    # - Font metadata (name, version, copyright, etc.)
    # - Extended text metrics
    #
    # @example Parse a PFM file
    #   pfm = Fontisan::Type1::PFMParser.parse_file("font.pfm")
    #   puts pfm.font_name
    #   puts pfm.character_widths['A']
    #   puts pfm.kerning_pairs[['A', 'V']]
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5005.PFM_Spec.pdf
    class PFMParser
      # PFM Header structure
      PFM_HEADER_SIZE = 256
      PFM_VERSION = 0x0100

      # @return [String] Font name
      attr_reader :font_name

      # @return [String] Full name
      attr_reader :full_name

      # @return [String] Family name
      attr_reader :family_name

      # @return [String] Copyright notice
      attr_reader :copyright

      # @return [Hash<String, Integer>] Character widths (glyph index => width)
      attr_reader :character_widths

      # @return [Hash<Array(Integer), Integer>] Kerning pairs ([left_idx, right_idx] => adjustment)
      attr_reader :kerning_pairs

      # @return [Hash] Extended text metrics
      attr_reader :extended_metrics

      # @return [Integer] Font bounding box [llx, lly, urx, ury]
      attr_reader :font_bbox

      # @return [String] Raw data
      attr_reader :raw_data

      # Parse PFM file
      #
      # @param path [String] Path to PFM file
      # @return [PFMParser] Parsed PFM data
      # @raise [ArgumentError] If path is nil
      # @raise [Fontisan::Error] If file cannot be read or parsed
      def self.parse_file(path)
        raise ArgumentError, "Path cannot be nil" if path.nil?

        unless File.exist?(path)
          raise Fontisan::Error, "PFM file not found: #{path}"
        end

        content = File.binread(path)
        parse(content)
      end

      # Parse PFM content
      #
      # @param content [String] PFM file content (binary)
      # @return [PFMParser] Parsed PFM data
      def self.parse(content)
        new.parse(content)
      end

      # Alias for parse method
      def self.parse_string(content)
        parse(content)
      end

      # Initialize a new PFMParser
      def initialize
        @character_widths = {}
        @kerning_pairs = {}
        @extended_metrics = {}
        @font_bbox = nil
      end

      # Parse PFM content
      #
      # @param content [String] PFM file content (binary)
      # @return [PFMParser] Self for method chaining
      def parse(content)
        @raw_data = content
        parse_header(content)
        parse_driver_info(content)
        parse_extended_metrics(content)
        parse_character_widths(content)
        parse_kerning_pairs(content)
        self
      end

      # Get character width for character index
      #
      # @param char_index [Integer] Character index
      # @return [Integer, nil] Character width or nil if not found
      def width(char_index)
        @character_widths[char_index]
      end

      # Get kerning adjustment for character pair
      #
      # @param left_idx [Integer] Left character index
      # @param right_idx [Integer] Right character index
      # @return [Integer, nil] Kerning adjustment or nil if not found
      def kerning(left_idx, right_idx)
        @kerning_pairs[[left_idx, right_idx]]
      end

      # Check if character exists
      #
      # @param char_index [Integer] Character index
      # @return [Boolean] True if character exists
      def has_character?(char_index)
        @character_widths.key?(char_index)
      end

      private

      # Parse PFM header
      #
      # @param content [String] PFM content
      def parse_header(content)
        # Read first 256 bytes as header
        return if content.length < PFM_HEADER_SIZE

        # Version (2 bytes at offset 0)
        read_uint16(content, 0)
        # dfVersion = version

        # Size info (4 bytes at offset 2)
        # dfSize = read_uint32(content, 2)

        # Copyright (60 bytes at offset 6)
        @copyright = read_pascal_string(content[6, 60])

        # Font type (2 bytes at offset 66)
        # dfType = read_uint16(content, 66)

        # Points (2 bytes at offset 68)
        # dfPoints = read_uint16(content, 68)

        # VertRes (2 bytes at offset 70)
        # dfVertRes = read_uint16(content, 70)

        # HorizRes (2 bytes at offset 72)
        # dfHorizRes = read_uint16(content, 72)

        # Ascent (2 bytes at offset 74)
        # dfAscent = read_uint16(content, 74)

        # InternalLeading (2 bytes at offset 76)
        # dfInternalLeading = read_uint16(content, 76)

        # ExternalLeading (2 bytes at offset 78)
        # dfExternalLeading = read_uint16(content, 78)

        # Italic (1 byte at offset 80)
        # dfItalic = content.getbyte(80)

        # Underline (1 byte at offset 81)
        # dfUnderline = content.getbyte(81)

        # StrikeOut (1 byte at offset 82)
        # dfStrikeOut = content.getbyte(82)

        # Weight (2 bytes at offset 83)
        # dfWeight = read_uint16(content, 83)

        # CharSet (1 byte at offset 85)
        # dfCharSet = content.getbyte(85)

        # PixWidth (2 bytes at offset 86)
        # dfPixWidth = read_uint16(content, 86)

        # PixHeight (2 bytes at offset 88)
        # dfPixHeight = read_uint16(content, 88)

        # PitchAndFamily (1 byte at offset 90)
        # dfPitchAndFamily = content.getbyte(90)

        # AverageWidth (2 bytes at offset 91)
        # dfAverageWidth = read_uint16(content, 91)

        # MaxWidth (2 bytes at offset 93)
        # dfMaxWidth = read_uint16(content, 93)

        # FirstChar (1 byte at offset 95)
        # dfFirstChar = content.getbyte(95)

        # LastChar (1 byte at offset 96)
        # dfLastChar = content.getbyte(96)

        # DefaultChar (1 byte at offset 97)
        # dfDefaultChar = content.getbyte(97)

        # BreakChar (1 byte at offset 98)
        # dfBreakChar = content.getbyte(98)

        # WidthBytes (2 bytes at offset 99)
        # dfWidthBytes = read_uint16(content, 99)

        # Device (4 bytes at offset 101)
        # dfDevice = read_uint32(content, 101)

        # Face (4 bytes at offset 105)
        # dfFace = read_uint32(content, 105)

        # Device name (usually empty in PFM)
        # BitsPointer (4 bytes at offset 109)
        # dfBitsPointer = read_uint32(content, 109)

        # BitsOffset (4 bytes at offset 113)
        # dfBitsOffset = read_uint32(content, 113)

        # Font name offset (4 bytes at offset 117)
        @dfFace_offset = read_uint32(content, 105)

        # Ext metrics offset (4 bytes at offset 117)
        @dfExtMetrics_offset = read_uint32(content, 117)

        # Ext table offset (4 bytes at offset 121)
        @dfExtentTable_offset = read_uint32(content, 121)

        # Origin table offset (4 bytes at offset 125)
        # dfOriginTable = read_uint32(content, 125)

        # PairKernTable offset (4 bytes at offset 129)
        @dfPairKernTable_offset = read_uint32(content, 129)

        # TrackKernTable offset (4 bytes at offset 133)
        # dfTrackKernTable = read_uint32(content, 133)

        # DriverInfo offset (4 bytes at offset 137)
        @dfDriverInfo_offset = read_uint32(content, 137)

        # Reserved (4 bytes at offset 141)
        # dfReserved = read_uint32(content, 141)

        # Signature (4 bytes at offset 145)
        # dfSignature = read_uint32(content, 145)
      end

      # Parse driver info to get font name
      #
      # @param content [String] PFM content
      def parse_driver_info(content)
        return unless @dfFace_offset&.positive?

        # Read font name at dfFace offset (byte 105 in header)
        # Font name is a Pascal-style string
        offset = @dfFace_offset
        return if offset >= content.length

        @font_name = read_pascal_string(content[offset..])
      end

      # Parse extended text metrics
      #
      # @param content [String] PFM content
      def parse_extended_metrics(content)
        return unless @dfExtMetrics_offset&.positive?

        offset = @dfExtMetrics_offset
        return if offset + 48 > content.length

        # Extended text metrics are 48 bytes
        # etmSize (4 bytes)
        # etmPointSize (4 bytes)
        # etmOrientation (4 bytes)
        # etmMasterHeight (4 bytes)
        # etmMinScale (4 bytes)
        # etmMaxScale (4 bytes)
        # etmMasterUnits (4 bytes)
        # etmCapHeight (4 bytes)
        # etmXHeight (4 bytes)
        # etmLowerCaseAscent (4 bytes)
        # etmLowerCaseDescent (4 bytes)
        # etmSlant (4 bytes)
        # etmSuperScript (4 bytes)
        # etmSubScript (4 bytes)
        # etmSuperScriptSize (4 bytes)
        # etmSubScriptSize (4 bytes)
        # etmUnderlineOffset (4 bytes)
        # etmUnderlineWidth (4 bytes)
        # etmDoubleUpperUnderlineOffset (4 bytes)
        # etmDoubleLowerUnderlineOffset (4 bytes)
        # etmDoubleUpperUnderlineWidth (4 bytes)
        # etmDoubleLowerUnderlineWidth (4 bytes)
        # etmStrikeOutOffset (4 bytes)
        # etmStrikeOutWidth (4 bytes)
        # etmKernPairs (4 bytes)
        # etmKernTracks (4 bytes)

        # Just read some key metrics
        @extended_metrics[:cap_height] = read_int32(content, offset + 28)
        @extended_metrics[:x_height] = read_int32(content, offset + 32)
      end

      # Parse character width table
      #
      # @param content [String] PFM content
      def parse_character_widths(content)
        return unless @dfExtentTable_offset&.positive?

        offset = @dfExtentTable_offset
        return if offset >= content.length

        # Read extent table
        # The extent table is an array of 2-byte values
        # First value is the number of extents
        num_extents = read_uint16(content, offset)
        offset += 2

        num_extents.times do |i|
          break if offset + 2 > content.length

          width = read_uint16(content, offset)
          @character_widths[i] = width
          offset += 2
        end
      end

      # Parse kerning pairs
      #
      # @param content [String] PFM content
      def parse_kerning_pairs(content)
        return unless @dfPairKernTable_offset&.positive?

        offset = @dfPairKernTable_offset
        return if offset >= content.length

        # Read number of kern pairs (2 bytes)
        num_pairs = read_uint16(content, offset)
        return if num_pairs.zero?

        offset += 2
        # Skip size info (2 bytes)
        offset += 2

        # Each kern pair is 6 bytes:
        # - First character index (2 bytes)
        # - Second character index (2 bytes)
        # - Kerning amount (2 bytes)
        num_pairs.times do
          break if offset + 6 > content.length

          first = read_uint16(content, offset)
          second = read_uint16(content, offset + 2)
          amount = read_int16(content, offset + 4)

          @kerning_pairs[[first, second]] = amount
          offset += 6
        end
      end

      # Read 16-bit unsigned integer (little-endian)
      #
      # @param data [String] Binary data
      # @param offset [Integer] Offset to read from
      # @return [Integer] 16-bit unsigned integer
      def read_uint16(data, offset)
        return 0 if offset + 2 > data.length

        data.getbyte(offset) | (data.getbyte(offset + 1) << 8)
      end

      # Read 32-bit unsigned integer (little-endian)
      #
      # @param data [String] Binary data
      # @param offset [Integer] Offset to read from
      # @return [Integer] 32-bit unsigned integer
      def read_uint32(data, offset)
        return 0 if offset + 4 > data.length

        data.getbyte(offset) |
          (data.getbyte(offset + 1) << 8) |
          (data.getbyte(offset + 2) << 16) |
          (data.getbyte(offset + 3) << 24)
      end

      # Read 32-bit signed integer (little-endian)
      #
      # @param data [String] Binary data
      # @param offset [Integer] Offset to read from
      # @return [Integer] 32-bit signed integer
      def read_int32(data, offset)
        value = read_uint32(data, offset)
        # Convert to signed
        value >= 0x80000000 ? value - 0x100000000 : value
      end

      # Read 16-bit signed integer (little-endian)
      #
      # @param data [String] Binary data
      # @param offset [Integer] Offset to read from
      # @return [Integer] 16-bit signed integer
      def read_int16(data, offset)
        value = read_uint16(data, offset)
        # Convert to signed
        value >= 0x8000 ? value - 0x10000 : value
      end

      # Read Pascal-style string
      #
      # @param data [String] Binary data starting with length byte
      # @return [String] String value
      def read_pascal_string(data)
        return "" if data.nil? || data.empty?

        length = data.getbyte(0)
        return "" if length.nil? || length.zero? || length > data.length - 1

        data[1, length].to_s.force_encoding("ASCII-8BIT").encode("UTF-8",
                                                                 invalid: :replace, undef: :replace)
      end
    end
  end
end
