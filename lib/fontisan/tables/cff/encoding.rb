# frozen_string_literal: true

require "stringio"
require_relative "../../binary/base_record"

module Fontisan
  module Tables
    class Cff
      # CFF Encoding structure
      #
      # Encoding maps character codes to glyph IDs (GIDs).
      # GID 0 (.notdef) is not encoded.
      #
      # Three formats:
      # - Format 0: Array of codes (one per glyph)
      # - Format 1: Ranges of consecutive codes
      # - Format 0/1 with supplement: Format 0 or 1 with additional mappings
      #
      # Predefined encodings:
      # - 0: Standard encoding (Adobe standard character set)
      # - 1: Expert encoding (Adobe expert character set)
      #
      # Reference: CFF specification section 14 "Encodings"
      # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
      #
      # @example Reading an Encoding
      #   encoding = Fontisan::Tables::Cff::Encoding.new(data, num_glyphs)
      #   puts encoding.glyph_id(65)      # => GID for char code 65 ('A')
      #   puts encoding.char_code(5)      # => char code for GID 5
      class Encoding
        # Predefined encoding identifiers
        PREDEFINED = {
          0 => :standard,
          1 => :expert,
        }.freeze

        # Format mask to extract format type
        FORMAT_MASK = 0x7F

        # @return [Integer] Encoding format (0 or 1)
        attr_reader :format_type

        # @return [Hash<Integer, Integer>] Map from character code to GID
        attr_reader :code_to_gid

        # @return [Hash<Integer, Integer>] Map from GID to character code
        attr_reader :gid_to_code

        # Initialize an Encoding
        #
        # @param data [String, Integer] Binary data or predefined encoding ID
        # @param num_glyphs [Integer] Number of glyphs in the font
        def initialize(data, num_glyphs)
          @num_glyphs = num_glyphs
          @code_to_gid = {}
          @gid_to_code = {}

          # GID 0 (.notdef) is always at code 0
          @code_to_gid[0] = 0
          @gid_to_code[0] = 0

          if data.is_a?(Integer) && PREDEFINED.key?(data)
            load_predefined_encoding(data)
          else
            @data = data
            parse!
          end
        end

        # Get GID for a character code
        #
        # @param code [Integer] Character code (0-255)
        # @return [Integer, nil] Glyph ID or nil if not mapped
        def glyph_id(code)
          @code_to_gid[code]
        end

        # Get character code for a GID
        #
        # @param gid [Integer] Glyph ID
        # @return [Integer, nil] Character code or nil if not mapped
        def char_code(gid)
          @gid_to_code[gid]
        end

        # Get the format symbol
        #
        # @return [Symbol] Format identifier (:array, :range, or :predefined)
        def format
          return :predefined unless @format_type

          @format_type.zero? ? :array : :range
        end

        # Check if encoding has supplement
        #
        # @return [Boolean] True if encoding has supplemental mappings
        def has_supplement?
          @has_supplement || false
        end

        private

        # Parse the Encoding from binary data
        def parse!
          io = StringIO.new(@data)
          format_byte = read_uint8(io)

          # Extract format (lower 7 bits) and supplement flag (bit 7)
          @format_type = format_byte & FORMAT_MASK
          @has_supplement = (format_byte & 0x80) != 0

          case @format_type
          when 0
            parse_format_0(io)
          when 1
            parse_format_1(io)
          else
            raise CorruptedTableError,
                  "Invalid Encoding format: #{@format_type}"
          end

          # Parse supplemental encoding if present
          parse_supplement(io) if @has_supplement
        rescue StandardError => e
          raise CorruptedTableError,
                "Failed to parse Encoding: #{e.message}"
        end

        # Parse Format 0: Array of codes
        #
        # Format 0 directly lists character codes for each glyph (except
        # .notdef)
        #
        # @param io [StringIO] Input stream positioned after format byte
        def parse_format_0(io)
          n_codes = read_uint8(io)

          # Read one code per glyph (GIDs start at 1, skipping .notdef)
          n_codes.times do |i|
            code = read_uint8(io)
            gid = i + 1 # GID 0 is .notdef, so start at 1

            @code_to_gid[code] = gid
            @gid_to_code[gid] = code
          end
        end

        # Parse Format 1: Ranges of codes
        #
        # Format 1 uses ranges: first code, nLeft (number of consecutive codes)
        #
        # @param io [StringIO] Input stream positioned after format byte
        def parse_format_1(io)
          n_ranges = read_uint8(io)
          gid = 1 # Start at GID 1 (skip .notdef at 0)

          n_ranges.times do
            first_code = read_uint8(io)
            n_left = read_uint8(io)

            # Map the range of codes
            (n_left + 1).times do |i|
              code = first_code + i
              @code_to_gid[code] = gid
              @gid_to_code[gid] = code
              gid += 1
            end
          end
        end

        # Parse supplemental encoding
        #
        # Supplemental encoding provides additional code-to-GID mappings
        #
        # @param io [StringIO] Input stream positioned after main encoding data
        def parse_supplement(io)
          n_sups = read_uint8(io)

          n_sups.times do
            read_uint8(io)
            read_uint16(io)

            # Find GID for this SID (requires charset lookup)
            # For now, we'll store the code mapping
            # A full implementation would need charset access to resolve SID to
            # GID
            # This is typically used when the charset has glyphs not in the
            # standard encoding
          end
        end

        # Load a predefined encoding
        #
        # @param encoding_id [Integer] Predefined encoding ID (0 or 1)
        def load_predefined_encoding(encoding_id)
          @format_type = nil # Predefined encodings don't have a format

          case encoding_id
          when 0
            load_standard_encoding
          when 1
            load_expert_encoding
          end
        end

        # Load Standard encoding
        #
        # Adobe Standard Encoding is the default encoding for Type 1 fonts
        # It maps common Latin characters to specific codes
        def load_standard_encoding
          # Standard encoding for common characters (codes 0-255)
          # This is a simplified version - a full implementation would include
          # all 256 standard encoding mappings from the CFF specification
          # Appendix B

          # Common ASCII mappings (basic Latin)
          gid = 1
          (32..126).each do |code|
            @code_to_gid[code] = gid
            @gid_to_code[gid] = code
            gid += 1
            break if gid >= @num_glyphs
          end
        end

        # Load Expert encoding
        #
        # Adobe Expert Encoding is used for expert fonts with special
        # characters like small caps, old-style figures, ligatures, etc.
        def load_expert_encoding
          # Expert encoding for special characters
          # This is a simplified version - a full implementation would include
          # all expert encoding mappings from the CFF specification Appendix C

          # Map some common expert characters
          gid = 1
          expert_codes = [32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
                          45, 46, 47]
          expert_codes.each do |code|
            @code_to_gid[code] = gid if gid < @num_glyphs
            @gid_to_code[gid] = code if gid < @num_glyphs
            gid += 1
            break if gid >= @num_glyphs
          end
        end

        # Read an unsigned 8-bit integer
        #
        # @param io [StringIO] Input stream
        # @return [Integer] The value
        def read_uint8(io)
          byte = io.read(1)
          raise CorruptedTableError, "Unexpected end of Encoding data" if
            byte.nil?

          byte.unpack1("C")
        end

        # Read an unsigned 16-bit integer (big-endian)
        #
        # @param io [StringIO] Input stream
        # @return [Integer] The value
        def read_uint16(io)
          bytes = io.read(2)
          raise CorruptedTableError, "Unexpected end of Encoding data" if
            bytes.nil? || bytes.bytesize < 2

          bytes.unpack1("n") # Big-endian unsigned 16-bit
        end
      end
    end
  end
end
