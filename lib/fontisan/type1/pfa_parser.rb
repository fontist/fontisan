# frozen_string_literal: true

module Fontisan
  module Type1
    # Parser for PFA (Printer Font ASCII) format
    #
    # [`PFAparser`](lib/fontisan/type1/pfa_parser.rb) parses the ASCII PFA format
    # used for storing Adobe Type 1 fonts, primarily on Unix/Linux systems.
    #
    # The PFA format is pure ASCII text with encrypted portions marked by
    # `currentfile eexec` and terminated by 512 ASCII zeros.
    #
    # Format structure:
    # - Clear text: Font dictionary and initial data
    # - Encrypted portion: Starts with `currentfile eexec`
    # - Encrypted data: Binary data encoded as hexadecimal
    # - End marker: 512 ASCII zeros ('0')
    # - Cleartext again: Font dictionary closing
    #
    # @example Parse a PFA file
    #   parser = Fontisan::Type1::PFAparser.new
    #   result = parser.parse(File.read('font.pfa'))
    #   puts result.clear_text    # => "!PS-AdobeFont-1.0..."
    #   puts result.encrypted_hex # => Encrypted hex string
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class PFAParser
      # Markers in PFA format
      EEXEC_MARKER = "currentfile eexec"
      # 512 ASCII zeros mark the end of encrypted portion
      ZERO_MARKER = "0" * 512

      # @return [String] Clear text portion (before eexec)
      attr_reader :clear_text

      # @return [String] Encrypted portion as hex string
      attr_reader :encrypted_hex

      # @return [String] Encrypted portion as binary data
      attr_reader :encrypted_binary

      # @return [String] Trailing text after zeros (if any)
      attr_reader :trailing_text

      # Parse PFA format data
      #
      # Handles both standard PFA (hex-encoded encrypted data with zero marker)
      # and .t1 format (binary encrypted data without zero marker).
      #
      # @param data [String] ASCII PFA data or .t1 format data
      # @return [PFAParser] Self for method chaining
      # @raise [ArgumentError] If data is nil or empty
      # @raise [Fontisan::Error] If PFA format is invalid
      def parse(data)
        raise ArgumentError, "Data cannot be nil" if data.nil?
        raise ArgumentError, "Data cannot be empty" if data.empty?

        # Normalize line endings
        data = normalize_line_endings(data)

        # Find eexec marker
        eexec_index = data.index(EEXEC_MARKER)
        if eexec_index.nil?
          # No eexec marker - entire file is clear text
          @clear_text = data
          @encrypted_hex = ""
          @encrypted_binary = ""
          @trailing_text = ""
          return self
        end

        # Clear text is everything before and including eexec marker
        @clear_text = data[0...eexec_index + EEXEC_MARKER.length]

        # Look for zeros after eexec marker
        after_eexec = data[eexec_index + EEXEC_MARKER.length..]

        # Skip whitespace after eexec marker
        encrypted_start = skip_whitespace(after_eexec, 0)
        encrypted_data = after_eexec[encrypted_start..]

        # Find zero marker (optional for .t1 format)
        zero_index = encrypted_data.index(ZERO_MARKER)

        if zero_index
          # Standard PFA format with zero marker
          # Extract encrypted hex data (before zeros)
          @encrypted_hex = encrypted_data[0...zero_index].strip
          @encrypted_binary = [@encrypted_hex.gsub(/\s/, "")].pack("H*")

          # Extract trailing text (after zeros)
          trailing_start = zero_index + ZERO_MARKER.length
          trailing_start = skip_whitespace(encrypted_data, trailing_start)

          @trailing_text = if trailing_start < encrypted_data.length
                             encrypted_data[trailing_start..]
                           else
                             ""
                           end
        else
          # .t1 format - binary encrypted data without zero marker
          # Treat everything after eexec as binary encrypted data
          @encrypted_binary = encrypted_data.lstrip
          @encrypted_hex = @encrypted_binary.unpack1("H*")
          @trailing_text = ""
        end

        self
      end

      # Check if parser has parsed data
      #
      # @return [Boolean] True if data has been parsed
      def parsed?
        !@clear_text.nil?
      end

      # Check if this appears to be a PFA file
      #
      # @param data [String] Text data to check
      # @return [Boolean] True if data appears to be PFA format
      #
      # @example Check if file is PFA format
      #   if Fontisan::Type1::PFAParser.pfa_file?(data)
      #     # Handle PFA format
      #   end
      def self.pfa_file?(data)
        return false if data.nil?
        return false if data.length < 15

        # Check for Adobe Type 1 font header
        data.include?("%!PS-AdobeFont-1.0") ||
          data.include?("%!PS-Adobe-3.0 Resource-Font")
      end

      private

      # Normalize line endings to LF
      #
      # @param data [String] Input data
      # @return [String] Data with normalized line endings
      def normalize_line_endings(data)
        data.gsub("\r\n", "\n").gsub("\r", "\n")
      end

      # Skip whitespace in string
      #
      # @param str [String] Input string
      # @param offset [Integer] Starting offset
      # @return [Integer] Offset after skipping whitespace
      def skip_whitespace(str, offset)
        while offset < str.length && str[offset].match?(/\s/)
          offset += 1
        end
        offset
      end
    end
  end
end
