# frozen_string_literal: true

module Fontisan
  module Type1
    # Type 1 CharStrings parser
    #
    # [`CharStrings`](lib/fontisan/type1/charstrings.rb) parses and stores
    # the CharStrings dictionary from a Type 1 font, which contains
    # glyph outline descriptions.
    #
    # CharStrings in Type 1 fonts use a stack-based language with commands
    # for drawing curves, lines, and composite glyphs (via the seac operator).
    #
    # @example Parse CharStrings from decrypted font data
    #   charstrings = Fontisan::Type1::CharStrings.parse(decrypted_data, private_dict)
    #   outline = charstrings.outline_for("A")
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    class CharStrings
      # @return [Hash] Glyph name to CharString data mapping
      attr_reader :charstrings

      # @return [PrivateDict] Private dictionary for decryption
      attr_reader :private_dict

      # Parse CharStrings dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @param private_dict [PrivateDict] Private dictionary for lenIV
      # @return [CharStrings] Parsed CharStrings dictionary
      # @raise [Fontisan::Error] If CharStrings cannot be parsed
      #
      # @example Parse from decrypted font data
      #   charstrings = Fontisan::Type1::CharStrings.parse(decrypted_data, private_dict)
      def self.parse(data, private_dict = nil)
        new(private_dict).parse(data)
      end

      # Initialize a new CharStrings parser
      #
      # @param private_dict [PrivateDict, nil] Private dictionary for lenIV
      def initialize(private_dict = nil)
        @private_dict = private_dict || PrivateDict.new
        @charstrings = {}
      end

      # Parse CharStrings dictionary from decrypted Type 1 font data
      #
      # @param data [String] Decrypted Type 1 font data
      # @return [CharStrings] Self for method chaining
      def parse(data)
        extract_charstrings(data)
        decrypt_charstrings
        self
      end

      # Get list of glyph names
      #
      # @return [Array<String>] Glyph names
      def glyph_names
        @charstrings.keys
      end

      # Get the number of charstrings
      #
      # @return [Integer] Number of charstrings
      def count
        @charstrings.size
      end

      # Get encoding map
      #
      # @return [Hash] Character code to glyph name mapping
      def encoding
        @encoding ||= build_standard_encoding
      end

      # Iterate over all charstrings
      #
      # @yield [glyph_name, charstring_data] Each glyph name and its charstring data
      # @return [Enumerator] If no block given
      def each_charstring(&)
        return enum_for(:each_charstring) unless block_given?

        @charstrings.each(&)
      end

      # Check if glyph exists
      #
      # @param glyph_name [String] Glyph name
      # @return [Boolean] True if glyph exists
      def has_glyph?(glyph_name)
        @charstrings.key?(glyph_name)
      end

      # Get CharString data for glyph
      #
      # @param glyph_name [String] Glyph name
      # @return [String, nil] CharString data or nil if not found
      def [](glyph_name)
        @charstrings[glyph_name]
      end

      # Alias for #[]
      #
      # @param glyph_name [String] Glyph name
      # @return [String, nil] CharString data or nil if not found
      def charstring(glyph_name)
        @charstrings[glyph_name]
      end

      # Get outline for glyph by name
      #
      # Parses the CharString and returns outline commands.
      #
      # @param glyph_name [String] Glyph name
      # @return [Array] Outline commands
      def outline_for(glyph_name)
        charstring = @charstrings[glyph_name]
        return nil if charstring.nil?

        parser = CharStringParser.new(@private_dict)
        parser.parse(charstring)
      end

      # Check if glyph is composite (uses seac)
      #
      # @param glyph_name [String] Glyph name
      # @return [Boolean] True if glyph uses seac operator
      def composite?(glyph_name)
        charstring = @charstrings[glyph_name]
        return false if charstring.nil?

        charstring.include?(SEAC_OPCODE)
      end

      # Get components for composite glyph
      #
      # @param glyph_name [String] Glyph name
      # @return [Hash, nil] Component info {:base, :accent} or nil
      def components_for(glyph_name)
        return nil unless composite?(glyph_name)

        charstring = @charstrings[glyph_name]
        parser = CharStringParser.new(@private_dict)
        parser.parse(charstring)

        parser.seac_components
      end

      private

      # Extract CharStrings dictionary from font data
      #
      # @param data [String] Decrypted Type 1 font data
      def extract_charstrings(data)
        # Find CharStrings dictionary
        # Format: /CharStrings <dict_size> dict def begin ... end
        #
        # The CharStrings dict contains entries like:
        #   /.notdef <index> CharString_data
        #   /A <index> CharString_data
        # etc.

        # Look for /CharStrings dict def begin ... end pattern
        charstrings_match = data.match(/\/CharStrings\s+.*?dict\s+(?:dup\s+)?begin(.*?)\/end/m)
        return if charstrings_match.nil?

        charstrings_text = charstrings_match[1]
        parse_charstrings_dict(charstrings_text)
      end

      # Parse CharStrings dictionary text
      #
      # @param text [String] CharStrings dictionary text
      def parse_charstrings_dict(text)
        # Type 1 CharStrings format:
        #   /glyphname <index> RD <binary_data>
        #   /glyphname <index> -| <binary_data> |-
        # where RD and -| mark binary data

        # Use a non-greedy match to capture data between the marker and end marker
        # For -| ... |- format:
        text.scan(/\/([^\s]+)\s+(\d+)\s+-\|(.*?)\|-/m) do |match|
          glyph_name = match[0]
          _index = match[1].to_i
          encrypted_data = match[2]

          @charstrings[glyph_name] = encrypted_data
        end

        # For RD format (no end marker, data ends at next glyph or end):
        # This is harder to parse, so we'll skip for now and focus on -| format
        # which is what PFB uses
      end

      # Decrypt all CharStrings
      def decrypt_charstrings
        len_iv = @private_dict.len_iv || 4

        @charstrings.transform_values! do |encrypted|
          # Check if data is binary (from PFB) or hex-encoded (from PFA)
          binary_data = if encrypted.ascii_only?
                          # Hex-encoded string (PFA format)
                          [encrypted.gsub(/\s/, "")].pack("H*")
                        else
                          # Already binary data (PFB format)
                          encrypted
                        end

          # Decrypt CharString
          Decryptor.charstring_decrypt(binary_data, len_iv: len_iv)
        end
      end

      # seac opcode
      SEAC_OPCODE = "\x0C\x06".b

      # Build standard encoding map
      #
      # @return [Hash] Standard encoding map (character code to glyph name)
      def build_standard_encoding
        # A subset of Adobe StandardEncoding
        {
          32 => "space", 33 => "exclam", 34 => "quotedbl", 35 => "numbersign",
          36 => "dollar", 37 => "percent", 38 => "ampersand", 39 => "quoteright",
          40 => "parenleft", 41 => "parenright", 42 => "asterisk", 43 => "plus",
          44 => "comma", 45 => "hyphen", 46 => "period", 47 => "slash",
          48 => "zero", 49 => "one", 50 => "two", 51 => "three",
          52 => "four", 53 => "five", 54 => "six", 55 => "seven",
          56 => "eight", 57 => "nine", 58 => "colon", 59 => "semicolon",
          60 => "less", 61 => "equal", 62 => "greater", 63 => "question",
          64 => "at",
          65 => "A", 66 => "B", 67 => "C", 68 => "D", 69 => "E",
          70 => "F", 71 => "G", 72 => "H", 73 => "I", 74 => "J",
          75 => "K", 76 => "L", 77 => "M", 78 => "N", 79 => "O",
          80 => "P", 81 => "Q", 82 => "R", 83 => "S", 84 => "T",
          85 => "U", 86 => "V", 87 => "W", 88 => "X", 89 => "Y",
          90 => "Z",
          91 => "bracketleft", 92 => "backslash", 93 => "bracketright",
          94 => "asciicircum", 95 => "underscore", 96 => "quoteleft",
          97 => "a", 98 => "b", 99 => "c", 100 => "d", 101 => "e",
          102 => "f", 103 => "g", 104 => "h", 105 => "i", 106 => "j",
          107 => "k", 108 => "l", 109 => "m", 110 => "n", 111 => "o",
          112 => "p", 113 => "q", 114 => "r", 115 => "s", 116 => "t",
          117 => "u", 118 => "v", 119 => "w", 120 => "x", 121 => "y",
          122 => "z",
          123 => "braceleft", 124 => "bar", 125 => "braceright",
          126 => "asciitilde"
        }
      end

      # CharString parser
      #
      # Parses Type 1 CharString bytecode into commands.
      class CharStringParser
        # @return [Array] Parsed commands
        attr_reader :commands

        # @return [Hash, nil] seac components if seac found
        attr_reader :seac_components

        # @return [PrivateDict] Private dictionary
        attr_reader :private_dict

        # Initialize parser
        #
        # @param private_dict [PrivateDict] Private dictionary
        def initialize(private_dict = nil)
          @private_dict = private_dict || PrivateDict.new
          @commands = []
          @seac_components = nil
        end

        # Parse CharString bytecode
        #
        # @param charstring [String] Binary CharString data
        # @return [Array] Parsed commands
        def parse(charstring)
          return [] if charstring.nil? || charstring.empty?

          @commands = []
          @seac_components = nil

          i = 0
          while i < charstring.length
            byte = charstring.getbyte(i)

            if byte <= 31
              # Operator
              parse_operator(charstring, byte, i)
              break if @seac_components # Stop at seac for now

              i += 1
            elsif byte == 255
              # Escaped number (2 bytes follow)
              num = charstring.getbyte(i + 1) |
                (charstring.getbyte(i + 2) << 8)
              num = num - 32768 if num >= 32768
              @commands << [:number, num]
              i += 3
            elsif byte >= 32 && byte <= 246
              # Small number (-107 to 107)
              num = byte - 139
              @commands << [:number, num]
              i += 1
            else
              # Unknown
              i += 1
            end
          end

          @commands
        end

        private

        # Parse operator
        #
        # @param charstring [String] Full CharString data
        # @param byte [Integer] Operator byte
        # @param offset [Integer] Current offset
        def parse_operator(charstring, byte, offset)
          case byte
          when 12
            # Two-byte operator
            next_byte = charstring.getbyte(offset + 1)
            parse_two_byte_operator(next_byte)
          when 1
            @commands << [:hstem]
          when 3
            @commands << [:vstem]
          when 4
            @commands << [:vmoveto]
          when 5
            @commands << [:rlineto]
          when 6
            @commands << [:hlineto]
          when 7
            @commands << [:vlineto]
          when 8
            @commands << [:rrcurveto]
          when 10
            @commands << [:callsubr]
          when 11
            @commands << [:return]
          when 14
            @commands << [:endchar]
          when 21
            @commands << [:rmoveto]
          when 22
            @commands << [:hmoveto]
          when 30
            @commands << [:vhcurveto]
          when 31
            @commands << [:hvcurveto]
          end
        end

        # Parse two-byte operator
        #
        # @param byte [Integer] Second operator byte
        def parse_two_byte_operator(byte)
          case byte
          when 6
            @commands << [:seac]
            parse_seac
          when 7
            @commands << [:sbw]
          when 34
            @commands << [:hsbw]
          when 36
            @commands << [:div]
          when 5
            @commands << [:callgsubr]
          end
        end

        # Parse seac composite glyph
        #
        # seac format: asb adx ady bchar achar seac
        def parse_seac
          # seac takes 5 arguments: asb, adx, ady, bchar, achar
          # We need to extract the last 5 numbers from the command stack
          nums = @commands.select { |c| c.first == :number }.map(&:last)

          return if nums.length < 5

          # Last two are bchar and achar (character codes)
          bchar = nums[-2]
          achar = nums[-1]
          adx = nums[-3]
          ady = nums[-4]

          @seac_components = {
            base: bchar,
            accent: achar,
            adx: adx,
            ady: ady,
          }
        end
      end
    end
  end
end
