# frozen_string_literal: true

module Fontisan
  module Type1
    # Parser for PFB (Printer Font Binary) format
    #
    # [`PFBParser`](lib/fontisan/type1/pfb_parser.rb) parses the binary PFB format
    # used for storing Adobe Type 1 fonts, primarily on Windows systems.
    #
    # The PFB format consists of binary chunks marked with special codes:
    # - 0x8001: ASCII text chunk
    # - 0x8002: Binary data chunk (usually encrypted)
    # - 0x8003: End of file marker
    #
    # Each chunk (except EOF) has a 4-byte little-endian length prefix.
    #
    # @example Parse a PFB file
    #   parser = Fontisan::Type1::PFBParser.new
    #   result = parser.parse(File.binread('font.pfb'))
    #   puts result.ascii_parts    # => ["%!PS-AdobeFont-1.0...", ...]
    #   puts result.binary_parts   # => [encrypted_binary_data, ...]
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class PFBParser
      # PFB chunk markers
      ASCII_CHUNK = 0x8001
      BINARY_CHUNK = 0x8002
      EOF_CHUNK = 0x8003

      # @return [Array<String>] ASCII text parts
      attr_reader :ascii_parts

      # @return [Array<String>] Binary data parts
      attr_reader :binary_parts

      # Parse PFB format data
      #
      # @param data [String] Binary PFB data
      # @return [PFBParser] Self for method chaining
      # @raise [ArgumentError] If data is nil or empty
      # @raise [Fontisan::Error] If PFB format is invalid
      def parse(data)
        raise ArgumentError, "Data cannot be nil" if data.nil?
        raise ArgumentError, "Data cannot be empty" if data.empty?

        @ascii_parts = []
        @binary_parts = []

        offset = 0
        chunk_index = 0

        while offset < data.length
          # Check for chunk marker (must have at least 2 bytes)
          if offset + 2 > data.length
            raise Fontisan::Error,
                  "Invalid PFB: incomplete chunk header at offset #{offset}"
          end

          # Read chunk marker (big-endian)
          marker = (data.getbyte(offset) << 8) |
            data.getbyte(offset + 1)
          offset += 2

          case marker
          when ASCII_CHUNK
            chunk = read_chunk(data, offset, chunk_index, "ASCII")
            @ascii_parts << chunk[:data]
            offset = chunk[:next_offset]
            chunk_index += 1

          when BINARY_CHUNK
            chunk = read_chunk(data, offset, chunk_index, "binary")
            @binary_parts << chunk[:data]
            offset = chunk[:next_offset]
            chunk_index += 1

          when EOF_CHUNK
            # End of file - no more chunks
            break

          else
            raise Fontisan::Error,
                  "Invalid PFB: unknown chunk marker 0x#{marker.to_s(16).upcase} at offset #{offset - 2}"
          end
        end

        self
      end

      # Get all ASCII parts concatenated
      #
      # @return [String] All ASCII parts joined together
      def ascii_text
        @ascii_parts.join
      end

      # Get all binary parts concatenated
      #
      # @return [String] All binary parts joined together
      def binary_data
        @binary_parts.join
      end

      # Check if parser has parsed data
      #
      # @return [Boolean] True if data has been parsed
      def parsed?
        !@ascii_parts.nil? && !@binary_parts.nil?
      end

      # Check if this appears to be a PFB file
      #
      # @param data [String] Binary data to check
      # @return [Boolean] True if data starts with PFB marker
      #
      # @example Check if file is PFB format
      #   if Fontisan::Type1::PFBParser.pfb_file?(data)
      #     # Handle PFB format
      #   end
      def self.pfb_file?(data)
        return false if data.nil? || data.length < 2

        # PFB marker is big-endian (first byte is high byte)
        marker = (data.getbyte(0) << 8) | data.getbyte(1)
        [ASCII_CHUNK, BINARY_CHUNK].include?(marker)
      end

      private

      # Read a chunk from PFB data
      #
      # @param data [String] PFB binary data
      # @param offset [Integer] Current offset in data
      # @param chunk_index [Integer] Index of current chunk (for error messages)
      # @param type [String] Type of chunk ("ASCII" or "binary")
      # @return [Hash] Chunk data with :data and :next_offset
      def read_chunk(data, offset, chunk_index, type)
        # Read 4-byte length (little-endian)
        if offset + 4 > data.length
          raise Fontisan::Error,
                "Invalid PFB: incomplete length for #{type} chunk #{chunk_index}"
        end

        length = data.getbyte(offset) |
          (data.getbyte(offset + 1) << 8) |
          (data.getbyte(offset + 2) << 16) |
          (data.getbyte(offset + 3) << 24)
        offset += 4

        # Read chunk data
        if offset + length > data.length
          raise Fontisan::Error,
                "Invalid PFB: #{type} chunk #{chunk_index} length #{length} exceeds remaining data"
        end

        chunk_data = data.byteslice(offset, length)
        next_offset = offset + length

        {
          data: chunk_data,
          next_offset: next_offset,
        }
      end
    end
  end
end
