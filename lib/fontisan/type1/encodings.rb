# frozen_string_literal: true

require_relative "agl"

module Fontisan
  module Type1
    # Font encoding schemes for Type 1 fonts
    #
    # [`Encodings`](lib/fontisan/type1/encodings.rb) provides encoding schemes that map
    # character positions to glyph names, following Adobe's encoding specifications.
    #
    # The Adobe Standard Encoding is the most common encoding for Type 1 fonts,
    # providing a consistent mapping of glyph names to character positions.
    #
    # @example Use Adobe Standard Encoding
    #   encoding = Fontisan::Type1::Encodings::AdobeStandard
    #   encoding.glyph_name_for_code(65)  # => "A"
    #   encoding.codepoint_for_glyph("A") # => 65
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5178.Type1.pdf
    module Encodings
      # Adobe Standard Encoding glyph list
      # This is the standard encoding used by most Type 1 fonts
      ADOBE_STANDARD = [
        ".notdef",        # 0
        "space",          # 1
        "exclam",         # 2
        "quotedbl",       # 3
        "numbersign",     # 4
        "dollar",         # 5
        "percent",        # 6
        "ampersand",      # 7
        "quoteright",     # 8
        "parenleft",      # 9
        "parenright",     # 10
        "asterisk",       # 11
        "plus",           # 12
        "comma",          # 13
        "hyphen",         # 14
        "period",         # 15
        "slash",          # 16
        "zero",           # 17
        "one",            # 18
        "two",            # 19
        "three",          # 20
        "four",           # 21
        "five",           # 22
        "six",            # 23
        "seven",          # 24
        "eight",          # 25
        "nine",           # 26
        "colon",          # 27
        "semicolon",      # 28
        "less",           # 29
        "equal",          # 30
        "greater",        # 31
        "question",       # 32
        "at",             # 33
        "A",              # 34
        "B",              # 35
        "C",              # 36
        "D",              # 37
        "E",              # 38
        "F",              # 39
        "G",              # 40
        "H",              # 41
        "I",              # 42
        "J",              # 43
        "K",              # 44
        "L",              # 45
        "M",              # 46
        "N",              # 47
        "O",              # 48
        "P",              # 49
        "Q",              # 50
        "R",              # 51
        "S",              # 52
        "T",              # 53
        "U",              # 54
        "V",              # 55
        "W",              # 56
        "X",              # 57
        "Y",              # 58
        "Z",              # 59
        "bracketleft",    # 60
        "backslash",      # 61
        "bracketright",   # 62
        "asciicircum",    # 63
        "underscore",     # 64
        "quoteleft",      # 65
        "a",              # 66
        "b",              # 67
        "c",              # 68
        "d",              # 69
        "e",              # 70
        "f",              # 71
        "g",              # 72
        "h",              # 73
        "i",              # 74
        "j",              # 75
        "k",              # 76
        "l",              # 77
        "m",              # 78
        "n",              # 79
        "o",              # 80
        "p",              # 81
        "q",              # 82
        "r",              # 83
        "s",              # 84
        "t",              # 85
        "u",              # 86
        "v",              # 87
        "w",              # 88
        "x",              # 89
        "y",              # 90
        "z",              # 91
        "braceleft",      # 92
        "bar",            # 93
        "braceright",     # 94
        "asciitilde",     # 95
        ".notdef",        # 96
        ".notdef",        # 97
        ".notdef",        # 98
        ".notdef",        # 99
        ".notdef",        # 100
        ".notdef",        # 101
        ".notdef",        # 102
        ".notdef",        # 103
        ".notdef",        # 104
        ".notdef",        # 105
        ".notdef",        # 106
        ".notdef",        # 107
        ".notdef",        # 108
        ".notdef",        # 109
        ".notdef",        # 110
        ".notdef",        # 111
        ".notdef",        # 112
        ".notdef",        # 113
        ".notdef",        # 114
        ".notdef",        # 115
        ".notdef",        # 116
        ".notdef",        # 117
        ".notdef",        # 118
        ".notdef",        # 119
        ".notdef",        # 120
        ".notdef",        # 121
        ".notdef",        # 122
        ".notdef",        # 123
        ".notdef",        # 124
        ".notdef",        # 125
        ".notdef",        # 126
        ".notdef",        # 127
        ".notdef",        # 128
        "exclamdown",     # 129
        "cent",           # 130
        "sterling",       # 131
        "fraction",       # 132
        "yen",            # 133
        "florin",         # 134
        "section",        # 135
        "currency",       # 136
        "quotesingle",    # 137
        "quotedblleft",   # 138
        "guillemotleft",  # 139
        "guilsinglleft",  # 140
        "guilsinglright", # 141
        "fi",             # 142
        "fl",             # 143
        ".notdef",        # 144
        "endash",         # 145
        "dagger",         # 146
        "daggerdbl",      # 147
        "periodcentered", # 148
        ".notdef",        # 149
        "paragraph",      # 150
        "bullet",         # 151
        "quotesinglbase", # 152
        "quotedblbase",   # 153
        "quotedblright",  # 154
        "guillemotright", # 155
        "ellipsis",       # 156
        "perthousand",    # 157
        ".notdef",        # 158
        "questiondown",   # 159
        ".notdef",        # 160
        "grave",          # 161
        "acute",          # 162
        "circumflex",     # 163
        "tilde",          # 164
        "macron",         # 165
        "breve",          # 166
        "dotaccent",      # 167
        "dieresis",       # 168
        ".notdef",        # 169
        "ring",           # 170
        "cedilla",        # 171
        ".notdef",        # 172
        "hungarumlaut",   # 173
        "ogonek",         # 174
        "caron",          # 175
        "emdash",         # 176
        ".notdef",        # 177
        ".notdef",        # 178
        ".notdef",        # 179
        ".notdef",        # 180
        ".notdef",        # 181
        ".notdef",        # 182
        ".notdef",        # 183
        ".notdef",        # 184
        ".notdef",        # 185
        ".notdef",        # 186
        ".notdef",        # 187
        ".notdef",        # 188
        ".notdef",        # 189
        ".notdef",        # 190
        ".notdef",        # 191
        "AE",             # 192
        ".notdef",        # 193
        "ordfeminine",    # 194
        ".notdef",        # 195
        ".notdef",        # 196
        ".notdef",        # 197
        ".notdef",        # 198
        "Lslash",         # 199
        "Oslash",         # 200
        "OE",             # 201
        "ordmasculine",   # 202
        ".notdef",        # 203
        ".notdef",        # 204
        ".notdef",        # 205
        ".notdef",        # 206
        ".notdef",        # 207
        ".notdef",        # 208
        "ae",             # 209
        ".notdef",        # 210
        ".notdef",        # 211
        ".notdef",        # 212
        "dotlessi",       # 213
        ".notdef",        # 214
        ".notdef",        # 215
        "lslash",         # 216
        "oslash",         # 217
        "oe",             # 218
        "germandbls",     # 219
        ".notdef",        # 220
        ".notdef",        # 221
        ".notdef",        # 222
        ".notdef",        # 223
        ".notdef",        # 224
        ".notdef",        # 225
        ".notdef",        # 226
        ".notdef",        # 227
        ".notdef",        # 228
        "Agrave",         # 229
        "Aacute",         # 230
        "Acircumflex",    # 231
        "Atilde",         # 232
        "Adieresis",      # 233
        "Aring",          # 234
        "Ccedilla",       # 235
        "Egrave",         # 236
        "Eacute",         # 237
        "Ecircumflex",    # 238
        "Edieresis",      # 239
        "Igrave",         # 240
        "Iacute",         # 241
        "Icircumflex",    # 242
        "Idieresis",      # 243
        "Eth",            # 244
        "Ntilde",         # 245
        "Ograve",         # 246
        "Oacute",         # 247
        "Ocircumflex",    # 248
        "Otilde",         # 249
        "Odieresis",      # 250
        "Ugrave",         # 251
        "Uacute",         # 252
        "Ucircumflex",    # 253
        "Udieresis",      # 254
        "Yacute",         # 255
      ].freeze

      # ISO-8859-1 (Latin-1) encoding glyph list
      ISO_8859_1 = [
        ".notdef",
        "space",
        "exclam",
        "quotedbl",
        "numbersign",
        "dollar",
        "percent",
        "ampersand",
        "quotesingle",
        "parenleft",
        "parenright",
        "asterisk",
        "plus",
        "comma",
        "hyphen",
        "period",
        "slash",
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "colon",
        "semicolon",
        "less",
        "equal",
        "greater",
        "question",
        "at",
        "A",
        "B",
        "C",
        "D",
        "E",
        "F",
        "G",
        "H",
        "I",
        "J",
        "K",
        "L",
        "M",
        "N",
        "O",
        "P",
        "Q",
        "R",
        "S",
        "T",
        "U",
        "V",
        "W",
        "X",
        "Y",
        "Z",
        "bracketleft",
        "backslash",
        "bracketright",
        "asciicircum",
        "underscore",
        "grave",
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
        "i",
        "j",
        "k",
        "l",
        "m",
        "n",
        "o",
        "p",
        "q",
        "r",
        "s",
        "t",
        "u",
        "v",
        "w",
        "x",
        "y",
        "z",
        "braceleft",
        "bar",
        "braceright",
        "asciitilde",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        ".notdef",
        "nobreakspace",
        "exclamdown",
        "cent",
        "sterling",
        "currency",
        "yen",
        "brokenbar",
        "section",
        "dieresis",
        "copyright",
        "ordfeminine",
        "guillemotleft",
        "logicalnot",
        "hyphen",
        "registered",
        "macron",
        "degree",
        "plusminus",
        "twosuperior",
        "threesuperior",
        "acute",
        "mu",
        "paragraph",
        "periodcentered",
        "cedilla",
        "onesuperior",
        "ordmasculine",
        "guillemotright",
        "onequarter",
        "onehalf",
        "threequarters",
        "questiondown",
        "Agrave",
        "Aacute",
        "Acircumflex",
        "Atilde",
        "Adieresis",
        "Aring",
        "AE",
        "Ccedilla",
        "Egrave",
        "Eacute",
        "Ecircumflex",
        "Edieresis",
        "Igrave",
        "Iacute",
        "Icircumflex",
        "Idieresis",
        "Eth",
        "Ntilde",
        "Ograve",
        "Oacute",
        "Ocircumflex",
        "Otilde",
        "Odieresis",
        "multiply",
        "Oslash",
        "Ugrave",
        "Uacute",
        "Ucircumflex",
        "Udieresis",
        "Yacute",
        "Thorn",
        "germandbls",
        "agrave",
        "aacute",
        "acircumflex",
        "atilde",
        "adieresis",
        "aring",
        "ae",
        "ccedilla",
        "egrave",
        "eacute",
        "ecircumflex",
        "edieresis",
        "igrave",
        "iacute",
        "icircumflex",
        "idieresis",
        "eth",
        "ntilde",
        "ograve",
        "oacute",
        "ocircumflex",
        "otilde",
        "odieresis",
        "divide",
        "oslash",
        "ugrave",
        "uacute",
        "ucircumflex",
        "udieresis",
        "yacute",
        "thorn",
        "ydieresis",
      ].freeze

      # Base encoding class
      #
      # All encoding classes should inherit from this and implement
      # the required methods.
      class Encoding
        # Get glyph name for character code
        #
        # @param codepoint [Integer] Character codepoint
        # @return [String, nil] Glyph name or nil if not found
        def self.glyph_name_for_code(codepoint)
          raise NotImplementedError,
                "#{name} must implement glyph_name_for_code"
        end

        # Get character code for glyph name
        #
        # @param name [String] Glyph name
        # @return [Integer, nil] Character code or nil if not found
        def self.codepoint_for_glyph(name)
          raise NotImplementedError,
                "#{name} must implement codepoint_for_glyph"
        end

        # Check if glyph name is in encoding
        #
        # @param name [String] Glyph name
        # @return [Boolean] True if glyph is in encoding
        def self.include?(name)
          !codepoint_for_glyph(name).nil?
        end

        # Get encoding name
        #
        # @return [String] Encoding name
        def self.encoding_name
          raise NotImplementedError, "#{name} must implement encoding_name"
        end

        # Get all glyph names in encoding
        #
        # @return [Array<String>] All glyph names
        def self.all_glyph_names
          raise NotImplementedError, "#{name} must implement all_glyph_names"
        end
      end

      # Adobe Standard Encoding
      #
      # The most common encoding for Type 1 fonts, providing a consistent
      # mapping of glyph names to character positions in the range 0-255.
      class AdobeStandard < Encoding
        # Build code to glyph mapping
        code_to_glyph = {}
        glyph_to_code = {}

        ADOBE_STANDARD.each_with_index do |name, i|
          code_to_glyph[i] = name unless name == ".notdef"
          glyph_to_code[name] = i unless name == ".notdef"
        end

        CODE_TO_GLYPH = code_to_glyph.freeze
        GLYPH_TO_CODE = glyph_to_code.freeze

        # Get glyph name for character code
        #
        # @param codepoint [Integer] Character code (0-255)
        # @return [String, nil] Glyph name or nil if not found
        def self.glyph_name_for_code(codepoint)
          CODE_TO_GLYPH[codepoint]
        end

        # Get character code for glyph name
        #
        # @param name [String] Glyph name
        # @return [Integer, nil] Character code or nil if not found
        def self.codepoint_for_glyph(name)
          GLYPH_TO_CODE[name]
        end

        # Get encoding name
        #
        # @return [String] "AdobeStandard"
        def self.encoding_name
          "AdobeStandard"
        end

        # Get all glyph names in encoding
        #
        # @return [Array<String>] All glyph names except .notdef
        def self.all_glyph_names
          ADOBE_STANDARD.reject { |n| n == ".notdef" }
        end
      end

      # ISO-8859-1 (Latin-1) Encoding
      #
      # Encoding for Western European languages, based on ISO-8859-1 standard.
      class ISOLatin1 < Encoding
        # Build code to glyph mapping
        code_to_glyph = {}
        glyph_to_code = {}

        ISO_8859_1.each_with_index do |name, i|
          code_to_glyph[i] = name unless name == ".notdef"
          glyph_to_code[name] = i unless name == ".notdef"
        end

        CODE_TO_GLYPH = code_to_glyph.freeze
        GLYPH_TO_CODE = glyph_to_code.freeze

        # Get glyph name for character code
        #
        # @param codepoint [Integer] Character code (0-255)
        # @return [String, nil] Glyph name or nil if not found
        def self.glyph_name_for_code(codepoint)
          CODE_TO_GLYPH[codepoint]
        end

        # Get character code for glyph name
        #
        # @param name [String] Glyph name
        # @return [Integer, nil] Character code or nil if not found
        def self.codepoint_for_glyph(name)
          GLYPH_TO_CODE[name]
        end

        # Get encoding name
        #
        # @return [String] "ISOLatin1"
        def self.encoding_name
          "ISOLatin1"
        end

        # Get all glyph names in encoding
        #
        # @return [Array<String>] All glyph names except .notdef
        def self.all_glyph_names
          ISO_8859_1.reject { |n| n == ".notdef" }
        end
      end

      # Unicode Encoding
      #
      # Uses the Adobe Glyph List to map Unicode codepoints to glyph names.
      # This encoding supports all Unicode characters through the AGL.
      class Unicode < Encoding
        # Get glyph name for Unicode codepoint
        #
        # @param codepoint [Integer] Unicode codepoint
        # @return [String] Glyph name from AGL
        def self.glyph_name_for_code(codepoint)
          AGL.glyph_name_for_unicode(codepoint)
        end

        # Get Unicode codepoint for glyph name
        #
        # @param name [String] Glyph name
        # @return [Integer, nil] Unicode codepoint or nil if not found
        def self.codepoint_for_glyph(name)
          AGL.unicode_for_glyph_name(name)
        end

        # Check if glyph name is in encoding (always true for Unicode)
        #
        # @param name [String] Glyph name
        # @return [Boolean] Always true for Unicode
        def self.include?(_name)
          true
        end

        # Get encoding name
        #
        # @return [String] "Unicode"
        def self.encoding_name
          "Unicode"
        end

        # Get all glyph names in AGL
        #
        # @return [Array<String>] All glyph names in AGL
        def self.all_glyph_names
          AGL.all_glyph_names
        end
      end
    end
  end
end
