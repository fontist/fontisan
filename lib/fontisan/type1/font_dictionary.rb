# frozen_string_literal: true

module Fontisan
  module Type1
    # Type 1 Font Dictionary model
    #
    # [`FontDictionary`](lib/fontisan/type1/font_dictionary.rb) parses and stores
    # the font dictionary from a Type 1 font, which contains metadata about
    # the font including FontInfo, FontName, Encoding, and other properties.
    #
    # The font dictionary is the top-level PostScript dictionary that defines
    # the font's properties and contains references to the Private dictionary
    # and CharStrings.
    #
    # @example Parse font dictionary from decrypted font data
    #   dict = Fontisan::Type1::FontDictionary.parse(decrypted_data)
    #   puts dict.font_name
    #   puts dict.font_info.full_name
    #   puts dict.font_b_box
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class FontDictionary
      # @return [FontInfo] Font information
      attr_reader :font_info

      # @return [String] Font name
      attr_reader :font_name

      # @return [Encoding] Font encoding
      attr_reader :encoding

      # @return [Hash] Font bounding box [x_min, y_min, x_max, y_max]
      attr_reader :font_b_box

      # Alias for font_b_box (camelCase compatibility)
      alias font_bbox font_b_box

      # @return [Array<Float>] Font matrix [xx, xy, yx, yy, tx, ty]
      attr_reader :font_matrix

      # @return [Integer] Paint type (0=symbol, 1=character)
      attr_reader :paint_type

      # @return [Integer] Font type (always 1 for Type 1)
      attr_reader :font_type

      # @return [Hash] Raw dictionary data
      attr_reader :raw_data

      # Parse font dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @return [FontDictionary] Parsed font dictionary
      # @raise [Fontisan::Error] If dictionary cannot be parsed
      #
      # @example Parse from decrypted font data
      #   dict = Fontisan::Type1::FontDictionary.parse(decrypted_data)
      def self.parse(data)
        new.parse(data)
      end

      # Initialize a new FontDictionary
      def initialize
        @font_info = FontInfo.new
        @encoding = Encoding.new
        @raw_data = {}
        @parsed = false
      end

      # Parse font dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @return [FontDictionary] Self for method chaining
      def parse(data)
        extract_font_dictionary(data)
        extract_font_info
        extract_encoding
        extract_properties
        @parsed = true
        self
      end

      # Check if dictionary was successfully parsed
      #
      # @return [Boolean] True if dictionary has been parsed
      def parsed?
        @parsed
      end

      # Get full name from FontInfo
      #
      # @return [String, nil] Full font name
      def full_name
        @font_info&.full_name
      end

      # Get family name from FontInfo
      #
      # @return [String, nil] Family name
      def family_name
        @font_info&.family_name
      end

      # Get version from FontInfo
      #
      # @return [String, nil] Font version
      def version
        @font_info&.version
      end

      # Get copyright from FontInfo
      #
      # @return [String, nil] Copyright notice
      def copyright
        @font_info&.copyright
      end

      # Get notice from FontInfo
      #
      # @return [String, nil] Notice string
      def notice
        @font_info&.notice
      end

      # Get weight from FontInfo
      #
      # @return [String, nil] Font weight (Thin, Light, Regular, Bold, etc.)
      def weight
        @font_info&.weight
      end

      # Get raw value from dictionary
      #
      # @param key [String] Dictionary key
      # @return [Object, nil] Value or nil if not found
      def [](key)
        @raw_data[key]
      end

      # Convert FontDictionary to Type 1 text format
      #
      # Generates the PostScript code for the Font Dictionary section
      # of a Type 1 font.
      #
      # @return [String] Type 1 Font Dictionary text
      #
      # @example Generate Type 1 format
      #   dict = FontDictionary.new
      #   puts dict.to_type1_format
      def to_type1_format
        result = []
        result << "% Type 1 Font Dictionary"
        result << "12 dict begin"
        result << ""
        result << "/FontType 1 def"
        result << "/PaintType #{@paint_type} def"
        result << font_matrix_to_type1
        result << font_bbox_to_type1
        result << ""
        result << font_info_to_type1
        result << ""
        result << "currentdict end"
        result << "/FontName #{@font_name} def"

        result.join("\n")
      end

      private

      # Extract font dictionary from data
      #
      # @param data [String] Decrypted Type 1 font data
      def extract_font_dictionary(data)
        # Find the font dictionary definition
        # Type 1 fonts use PostScript dictionary syntax
        # Format: /FontName dict def ... end
        #
        # We need to extract the dictionary between "dict def" and "end"

        # Look for dictionary pattern
        # The font dict typically starts after the version comment
        # and contains key-value pairs

        @raw_data = parse_dictionary(data)
      end

      # Parse PostScript dictionary from text
      #
      # @param text [String] PostScript text
      # @return [Hash] Parsed key-value pairs
      def parse_dictionary(text)
        result = {}

        # Find dict def ... end blocks
        # This is a simplified parser for Type 1 font dictionaries

        # Extract key-value pairs using regex
        # Patterns:
        #   /key value def
        #   /key (string) def
        #   /key [array] def
        #   /key number def

        # Parse FontName - use bounded pattern to prevent ReDoS
        # Font names are typically 1-64 characters of alphanumeric, dash, underscore
        if (match = text.match(%r{/FontName\s+/([A-Za-z0-9_-]{1,64})\s+def}m))
          result[:font_name] = match[1]
        end

        # Parse FontInfo entries
        # These are typically at the top level or in a FontInfo sub-dictionary
        # Format: /FullName (value) readonly def
        # Use safer patterns with bounded content and optional readonly keyword
        if (match = text.match(%r{/FullName\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:full_name] = match[1]
        end

        if (match = text.match(%r{/FamilyName\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:family_name] = match[1]
        end

        if (match = text.match(%r{/version\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:version] = match[1]
        end

        if (match = text.match(%r{/Copyright\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:copyright] = match[1]
        end

        if (match = text.match(%r{/Notice\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:notice] = match[1]
        end

        if (match = text.match(%r{/Weight\s+\(([^)]{1,128}?)\)\s+(?:readonly\s+)?def}m))
          result[:weight] = match[1]
        end

        if (match = text.match(%r{/isFixedPitch\s+(true|false)\s+def}m))
          result[:is_fixed_pitch] = match[1] == "true"
        end

        if (match = text.match(%r{/UnderlinePosition\s+(-?\d+)\s+def}m))
          result[:underline_position] = match[1].to_i
        end

        if (match = text.match(%r{/UnderlineThickness\s+(-?\d+)\s+def}m))
          result[:underline_thickness] = match[1].to_i
        end

        if (match = text.match(%r{/ItalicAngle\s+(-?\d+)\s+def}m))
          result[:italic_angle] = match[1].to_i
        end

        # Parse FontBBox - use safer patterns
        if (match = text.match(%r{/FontBBox\s*\{([^\}]{1,100}?)\}\s+(?:readonly\s+)?def}m))
          bbox_str = match[1].gsub(/[{}]/, "").strip.split
          result[:font_b_box] = bbox_str.map(&:to_i) if bbox_str.length >= 4
        elsif (match = text.match(%r{/FontBBox\s*\[([^\]]{1,100}?)\]\s+(?:readonly\s+)?def}m))
          bbox_str = match[1].strip.split
          result[:font_b_box] = bbox_str.map(&:to_i) if bbox_str.length >= 4
        end

        # Parse FontMatrix
        if (match = text.match(%r{/FontMatrix\s*\[([^\]]{1,100}?)\]\s+(?:readonly\s+)?def}m))
          matrix_str = match[1].strip.split
          result[:font_matrix] = matrix_str.map(&:to_f)
        end

        # Parse PaintType
        if (match = text.match(%r{/PaintType\s+(\d+)\s+def}m))
          result[:paint_type] = match[1].to_i
        end

        # Parse FontType
        if (match = text.match(%r{/FontType\s+(\d+)\s+def}m))
          result[:font_type] = match[1].to_i
        end

        result
      end

      # Extract FontInfo sub-dictionary
      def extract_font_info
        @font_info.parse(@raw_data)
      end

      # Extract encoding
      def extract_encoding
        @encoding.parse(@raw_data)
      end

      # Extract standard properties
      def extract_properties
        @font_name = @raw_data[:font_name]
        @font_b_box = @raw_data[:font_b_box] || [0, 0, 0, 0]
        @font_matrix = @raw_data[:font_matrix] || [0.001, 0, 0, 0.001, 0, 0]
        @paint_type = @raw_data[:paint_type] || 0
        @font_type = @raw_data[:font_type] || 1
      end

      # Format FontMatrix for Type 1 output
      #
      # @return [String] Formatted FontMatrix definition
      def font_matrix_to_type1
        "/FontMatrix [#{@font_matrix.join(' ')}] def"
      end

      # Format FontBBox for Type 1 output
      #
      # @return [String] Formatted FontBBox definition
      def font_bbox_to_type1
        "/FontBBox {#{@font_b_box.join(' ')}} def"
      end

      # Format FontInfo for Type 1 output
      #
      # @return [String] Formatted FontInfo definitions
      def font_info_to_type1
        info = @font_info
        result = []
        result << "/FullName (#{info.full_name || 'Untitled'}) readonly def" if info.full_name
        result << "/FamilyName (#{info.family_name || 'Untitled'}) readonly def" if info.family_name
        result << "/version (#{info.version || '001.000'}) readonly def" if info.version
        result << "/Copyright (#{info.copyright || ''}) readonly def" if info.copyright
        result << "/Notice (#{info.notice || ''}) readonly def" if info.notice
        result << "/Weight (#{info.weight || 'Medium'}) readonly def" if info.weight
        result << "/isFixedPitch #{info.is_fixed_pitch || false} def" if info.is_fixed_pitch
        result << "/UnderlinePosition #{info.underline_position || -100} def" if info.underline_position
        result << "/UnderlineThickness #{info.underline_thickness || 50} def" if info.underline_thickness
        result << "/ItalicAngle #{info.italic_angle || 0} def" if info.italic_angle

        result.join("\n")
      end

      # FontInfo sub-dictionary
      #
      # Contains font metadata such as FullName, FamilyName, version, etc.
      class FontInfo
        # @return [String, nil] Full font name
        attr_accessor :full_name

        # @return [String, nil] Family name
        attr_accessor :family_name

        # @return [String, nil] Font version
        attr_accessor :version

        # @return [String, nil] Copyright notice
        attr_accessor :copyright

        # @return [String, nil] Notice string
        attr_accessor :notice

        # @return [String, nil] Font weight (Thin, Light, Regular, Bold, etc.)
        attr_accessor :weight

        # @return [String, nil] Fixed pitch (monospace) indicator
        attr_accessor :is_fixed_pitch

        # @return [String, nil] Underline position
        attr_accessor :underline_position

        # @return [String, nil] Underline thickness
        attr_accessor :underline_thickness

        # @return [String, nil] Italic angle
        attr_accessor :italic_angle

        # Parse FontInfo from dictionary data
        #
        # @param dict_data [Hash] Raw dictionary data
        def parse(dict_data)
          # FontInfo can be embedded in the main dict or as a sub-dict
          # Try to extract from various patterns
          @full_name = extract_string_value(dict_data, "FullName")
          @family_name = extract_string_value(dict_data, "FamilyName")
          @version = extract_string_value(dict_data, "version")
          @copyright = extract_string_value(dict_data, "Copyright")
          @notice = extract_string_value(dict_data, "Notice")
          @weight = extract_string_value(dict_data, "Weight")
          @is_fixed_pitch = extract_value(dict_data, "isFixedPitch")
          @underline_position = extract_value(dict_data, "UnderlinePosition")
          @underline_thickness = extract_value(dict_data, "UnderlineThickness")
          @italic_angle = extract_value(dict_data, "ItalicAngle")
        end

        private

        # Extract string value from dictionary
        #
        # @param dict_data [Hash] Dictionary data
        # @param key [String] Key to extract
        # @return [String, nil] String value or nil
        def extract_string_value(dict_data, key)
          val = extract_value(dict_data, key)
          return nil if val.nil?

          # Remove parentheses if present
          val = val.to_s
          val = val[1..-2] if val.start_with?("(") && val.end_with?(")")
          val
        end

        # Extract value from dictionary
        #
        # @param dict_data [Hash] Dictionary data
        # @param key [String] Key to extract
        # @return [Object, nil] Value or nil
        def extract_value(dict_data, key)
          sym_key = key.to_sym
          return dict_data[sym_key] if dict_data.key?(sym_key)

          # Try underscore version (e.g., FullName => full_name)
          underscore_key = key.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/,
                                                                   "").to_sym
          dict_data[underscore_key]
        end
      end

      # Encoding vector
      #
      # Maps character codes to glyph names in the font.
      class Encoding
        # @return [Hash] Character code to glyph name mapping
        attr_reader :encoding_map

        # @return [Symbol] Encoding type (:standard, :custom, :identity)
        attr_reader :encoding_type

        def initialize
          @encoding_map = {}
          @encoding_type = :standard
        end

        # Parse encoding from dictionary data
        #
        # @param dict_data [Hash] Dictionary data
        def parse(dict_data)
          # Type 1 fonts typically use StandardEncoding by default
          # Custom encodings are specified as an array

          @encoding_type = if dict_data[:encoding]
                             :custom
                           else
                             :standard
                           end

          # Populate with StandardEncoding if standard
          populate_standard_encoding if @encoding_type == :standard
        end

        # Get glyph name for character code
        #
        # @param char_code [Integer] Character code
        # @return [String, nil] Glyph name or nil
        def [](char_code)
          @encoding_map[char_code]
        end

        # Check if encoding is standard
        #
        # @return [Boolean] True if using StandardEncoding
        def standard?
          @encoding_type == :standard
        end

        private

        # Populate with Adobe StandardEncoding
        def populate_standard_encoding
          # A subset of Adobe StandardEncoding
          # This is a simplified version for common characters
          standard_mapping = {
            32 => "space",
            33 => "exclam",
            34 => "quotedbl",
            35 => "numbersign",
            36 => "dollar",
            37 => "percent",
            38 => "ampersand",
            39 => "quoteright",
            40 => "parenleft",
            41 => "parenright",
            42 => "asterisk",
            43 => "plus",
            44 => "comma",
            45 => "hyphen",
            46 => "period",
            47 => "slash",
            48 => "zero",
            49 => "one",
            50 => "two",
            51 => "three",
            52 => "four",
            53 => "five",
            54 => "six",
            55 => "seven",
            56 => "eight",
            57 => "nine",
            58 => "colon",
            59 => "semicolon",
            60 => "less",
            61 => "equal",
            62 => "greater",
            63 => "question",
            64 => "at",
            65 => "A",
            66 => "B",
            67 => "C",
            68 => "D",
            69 => "E",
            70 => "F",
            71 => "G",
            72 => "H",
            73 => "I",
            74 => "J",
            75 => "K",
            76 => "L",
            77 => "M",
            78 => "N",
            79 => "O",
            80 => "P",
            81 => "Q",
            82 => "R",
            83 => "S",
            84 => "T",
            85 => "U",
            86 => "V",
            87 => "W",
            88 => "X",
            89 => "Y",
            90 => "Z",
            91 => "bracketleft",
            92 => "backslash",
            93 => "bracketright",
            94 => "asciicircum",
            95 => "underscore",
            96 => "quoteleft",
            97 => "a",
            98 => "b",
            99 => "c",
            100 => "d",
            101 => "e",
            102 => "f",
            103 => "g",
            104 => "h",
            105 => "i",
            106 => "j",
            107 => "k",
            108 => "l",
            109 => "m",
            110 => "n",
            111 => "o",
            112 => "p",
            113 => "q",
            114 => "r",
            115 => "s",
            116 => "t",
            117 => "u",
            118 => "v",
            119 => "w",
            120 => "x",
            121 => "y",
            122 => "z",
            123 => "braceleft",
            124 => "bar",
            125 => "braceright",
            126 => "asciitilde",
          }

          @encoding_map = standard_mapping
        end
      end
    end
  end
end
