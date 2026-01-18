# frozen_string_literal: true

module Fontisan
  module Type1
    # Adobe Glyph List (AGL) for Unicode to glyph name mapping
    #
    # [`AGL`](lib/fontisan/type1/agl.rb) provides mapping between Unicode codepoints
    # and glyph names according to the Adobe Glyph List Specification.
    #
    # The AGL defines standard names for glyphs to ensure compatibility across
    # font applications and systems.
    #
    # @see https://github.com/adobe-type-tools/agl-specification
    module AGL
      # Unicode to glyph name mapping (subset of AGL)
      # Includes commonly used glyphs from Latin-1 and Latin Extended-A
      UNICODE_TO_NAME = {
        # ASCII control characters and basic Latin
        0x0020 => "space",
        0x0021 => "exclam",
        0x0022 => "quotedbl",
        0x0023 => "numbersign",
        0x0024 => "dollar",
        0x0025 => "percent",
        0x0026 => "ampersand",
        0x0027 => "quotesingle",
        0x0028 => "parenleft",
        0x0029 => "parenright",
        0x002A => "asterisk",
        0x002B => "plus",
        0x002C => "comma",
        0x002D => "hyphen",
        0x002E => "period",
        0x002F => "slash",
        0x0030 => "zero",
        0x0031 => "one",
        0x0032 => "two",
        0x0033 => "three",
        0x0034 => "four",
        0x0035 => "five",
        0x0036 => "six",
        0x0037 => "seven",
        0x0038 => "eight",
        0x0039 => "nine",
        0x003A => "colon",
        0x003B => "semicolon",
        0x003C => "less",
        0x003D => "equal",
        0x003E => "greater",
        0x003F => "question",
        0x0040 => "at",
        0x0041 => "A",
        0x0042 => "B",
        0x0043 => "C",
        0x0044 => "D",
        0x0045 => "E",
        0x0046 => "F",
        0x0047 => "G",
        0x0048 => "H",
        0x0049 => "I",
        0x004A => "J",
        0x004B => "K",
        0x004C => "L",
        0x004D => "M",
        0x004E => "N",
        0x004F => "O",
        0x0050 => "P",
        0x0051 => "Q",
        0x0052 => "R",
        0x0053 => "S",
        0x0054 => "T",
        0x0055 => "U",
        0x0056 => "V",
        0x0057 => "W",
        0x0058 => "X",
        0x0059 => "Y",
        0x005A => "Z",
        0x005B => "bracketleft",
        0x005C => "backslash",
        0x005D => "bracketright",
        0x005E => "asciicircum",
        0x005F => "underscore",
        0x0060 => "grave",
        0x0061 => "a",
        0x0062 => "b",
        0x0063 => "c",
        0x0064 => "d",
        0x0065 => "e",
        0x0066 => "f",
        0x0067 => "g",
        0x0068 => "h",
        0x0069 => "i",
        0x006A => "j",
        0x006B => "k",
        0x006C => "l",
        0x006D => "m",
        0x006E => "n",
        0x006F => "o",
        0x0070 => "p",
        0x0071 => "q",
        0x0072 => "r",
        0x0073 => "s",
        0x0074 => "t",
        0x0075 => "u",
        0x0076 => "v",
        0x0077 => "w",
        0x0078 => "x",
        0x0079 => "y",
        0x007A => "z",
        0x007B => "braceleft",
        0x007C => "bar",
        0x007D => "braceright",
        0x007E => "asciitilde",
        # Latin-1 Supplement
        0x00A0 => "space",
        0x00A1 => "exclamdown",
        0x00A2 => "cent",
        0x00A3 => "sterling",
        0x00A4 => "currency",
        0x00A5 => "yen",
        0x00A6 => "brokenbar",
        0x00A7 => "section",
        0x00A8 => "dieresis",
        0x00A9 => "copyright",
        0x00AA => "ordfeminine",
        0x00AB => "guillemotleft",
        0x00AC => "logicalnot",
        0x00AD => "hyphen",
        0x00AE => "registered",
        0x00AF => "macron",
        0x00B0 => "degree",
        0x00B1 => "plusminus",
        0x00B2 => "twosuperior",
        0x00B3 => "threesuperior",
        0x00B4 => "acute",
        0x00B5 => "mu",
        0x00B6 => "paragraph",
        0x00B7 => "periodcentered",
        0x00B8 => "cedilla",
        0x00B9 => "onesuperior",
        0x00BA => "ordmasculine",
        0x00BB => "guillemotright",
        0x00BC => "onequarter",
        0x00BD => "onehalf",
        0x00BE => "threequarters",
        0x00BF => "questiondown",
        0x00C0 => "Agrave",
        0x00C1 => "Aacute",
        0x00C2 => "Acircumflex",
        0x00C3 => "Atilde",
        0x00C4 => "Adieresis",
        0x00C5 => "Aring",
        0x00C6 => "AE",
        0x00C7 => "Ccedilla",
        0x00C8 => "Egrave",
        0x00C9 => "Eacute",
        0x00CA => "Ecircumflex",
        0x00CB => "Edieresis",
        0x00CC => "Igrave",
        0x00CD => "Iacute",
        0x00CE => "Icircumflex",
        0x00CF => "Idieresis",
        0x00D0 => "Eth",
        0x00D1 => "Ntilde",
        0x00D2 => "Ograve",
        0x00D3 => "Oacute",
        0x00D4 => "Ocircumflex",
        0x00D5 => "Otilde",
        0x00D6 => "Odieresis",
        0x00D7 => "multiply",
        0x00D8 => "Oslash",
        0x00D9 => "Ugrave",
        0x00DA => "Uacute",
        0x00DB => "Ucircumflex",
        0x00DC => "Udieresis",
        0x00DD => "Yacute",
        0x00DE => "Thorn",
        0x00DF => "germandbls",
        0x00E0 => "agrave",
        0x00E1 => "aacute",
        0x00E2 => "acircumflex",
        0x00E3 => "atilde",
        0x00E4 => "adieresis",
        0x00E5 => "aring",
        0x00E6 => "ae",
        0x00E7 => "ccedilla",
        0x00E8 => "egrave",
        0x00E9 => "eacute",
        0x00EA => "ecircumflex",
        0x00EB => "edieresis",
        0x00EC => "igrave",
        0x00ED => "iacute",
        0x00EE => "icircumflex",
        0x00EF => "idieresis",
        0x00F0 => "eth",
        0x00F1 => "ntilde",
        0x00F2 => "ograve",
        0x00F3 => "oacute",
        0x00F4 => "ocircumflex",
        0x00F5 => "otilde",
        0x00F6 => "odieresis",
        0x00F7 => "divide",
        0x00F8 => "oslash",
        0x00F9 => "ugrave",
        0x00FA => "uacute",
        0x00FB => "ucircumflex",
        0x00FC => "udieresis",
        0x00FD => "yacute",
        0x00FE => "thorn",
        0x00FF => "ydieresis",
        # Latin Extended-A
        0x0100 => "Amacron",
        0x0101 => "amacron",
        0x0102 => "Abreve",
        0x0103 => "abreve",
        0x0104 => "Aogonek",
        0x0105 => "aogonek",
        0x0106 => "Cacute",
        0x0107 => "cacute",
        0x0108 => "Ccircumflex",
        0x0109 => "ccircumflex",
        0x010A => "Cdotaccent",
        0x010B => "cdotaccent",
        0x010C => "Ccaron",
        0x010D => "ccaron",
        0x010E => "Dcaron",
        0x010F => "dcaron",
        0x0110 => "Dcroat",
        0x0111 => "dcroat",
        0x0112 => "Emacron",
        0x0113 => "emacron",
        0x0114 => "Ebreve",
        0x0115 => "ebreve",
        0x0116 => "Edotaccent",
        0x0117 => "edotaccent",
        0x0118 => "Eogonek",
        0x0119 => "eogonek",
        0x011A => "Ecaron",
        0x011B => "ecaron",
        0x011C => "Gcircumflex",
        0x011D => "gcircumflex",
        0x011E => "Gbreve",
        0x011F => "gbreve",
        0x0120 => "Gdotaccent",
        0x0121 => "gdotaccent",
        0x0122 => "Gcommaaccent",
        0x0123 => "gcommaaccent",
        0x0124 => "Hcircumflex",
        0x0125 => "hcircumflex",
        0x0126 => "Hbar",
        0x0127 => "hbar",
        0x0128 => "Itilde",
        0x0129 => "itilde",
        0x012A => "Imacron",
        0x012B => "imacron",
        0x012C => "Ibreve",
        0x012D => "ibreve",
        0x012E => "Iogonek",
        0x012F => "iogonek",
        0x0130 => "Idotaccent",
        0x0131 => "dotlessi",
        0x0132 => "Lig",
        0x0133 => "lig",
        0x0134 => "Lslash",
        0x0135 => "lslash",
        0x0136 => "Nacute",
        0x0137 => "nacute",
        0x0138 => "kgreenlandic",
        0x0139 => "Ncommaaccent",
        0x013A => "ncommaaccent",
        0x013B => "Ncaron",
        0x013C => "ncaron",
        0x013D => "napostrophe",
        0x013E => "Eng",
        0x013F => "eng",
        0x0140 => "Omacron",
        0x0141 => "omacron",
        0x0142 => "Obreve",
        0x0143 => "obreve",
        0x0144 => "Ohungarumlaut",
        0x0145 => "ohungarumlaut",
        0x0146 => "Oogonek",
        0x0147 => "oogonek",
        0x0148 => "Racute",
        0x0149 => "racute",
        0x014A => "Rcaron",
        0x014B => "rcaron",
        0x014C => "Sacute",
        0x014D => "sacute",
        0x014E => "Scircumflex",
        0x014F => "scircumflex",
        0x0150 => "Scedilla",
        0x0151 => "scedilla",
        0x0152 => "Scaron",
        0x0153 => "scaron",
        0x0154 => "Tcommaaccent",
        0x0155 => "tcommaaccent",
        0x0156 => "Tcaron",
        0x0157 => "tcaron",
        0x0158 => "Tbar",
        0x0159 => "tbar",
        0x015A => "Utilde",
        0x015B => "utilde",
        0x015C => "Umacron",
        0x015D => "umacron",
        0x015E => "Ubreve",
        0x015F => "ubreve",
        0x0160 => "Uring",
        0x0161 => "uring",
        0x0162 => "Uhungarumlaut",
        0x0163 => "uhungarumlaut",
        0x0164 => "Uogonek",
        0x0165 => "uogonek",
        0x0166 => "Wcircumflex",
        0x0167 => "wcircumflex",
        0x0168 => "Ycircumflex",
        0x0169 => "ycircumflex",
        0x016A => "Zacute",
        0x016B => "zacute",
        0x016C => "Zdotaccent",
        0x016D => "zdotaccent",
        0x016E => "Zcaron",
        0x016F => "zcaron",
        0x0170 => "longs",
        0x0171 => "caron",
        0x0172 => "breve",
        0x0173 => "dotaccent",
        0x0174 => "ring",
        0x0175 => "ogonek",
        0x0176 => "tilde",
        0x0177 => "hungarumlaut",
        0x0178 => "commaaccent",
        0x0179 => "slash",
        0x017A => "hyphen",
        0x017B => "period",
        0x017F => "florin",
        # Greek (some common)
        0x0391 => "Alpha",
        0x0392 => "Beta",
        0x0393 => "Gamma",
        0x0394 => "Delta",
        0x0395 => "Epsilon",
        0x0396 => "Zeta",
        0x0397 => "Eta",
        0x0398 => "Theta",
        0x0399 => "Iota",
        0x039A => "Kappa",
        0x039B => "Lambda",
        0x039C => "Mu",
        0x039D => "Nu",
        0x039E => "Xi",
        0x039F => "Omicron",
        0x03A0 => "Pi",
        0x03A1 => "Rho",
        0x03A3 => "Sigma",
        0x03A4 => "Tau",
        0x03A5 => "Upsilon",
        0x03A6 => "Phi",
        0x03A7 => "Chi",
        0x03A8 => "Psi",
        0x03A9 => "Omega",
        # Currency and other symbols
        0x20AC => "Euro",
        0x2113 => "literalsign",
        0x2116 => "numerosign",
        0x2122 => "trademark",
        0x2126 => "Omega",
        0x212E => "estimated",
        0x2202 => "partialdiff",
        0x2206 => "Delta",
        0x220F => "product",
        0x2211 => "summation",
        0x221A => "radical",
        0x221E => "infinity",
        0x222B => "integral",
        0x2248 => "approxequal",
        0x2260 => "notequal",
        0x2264 => "lessequal",
        0x2265 => "greaterequal",
      }.freeze

      # Glyph name to Unicode mapping (inverse of UNICODE_TO_NAME)
      # When duplicates exist, uses the first (lowest) codepoint
      NAME_TO_UNICODE = begin
        result = {}
        UNICODE_TO_NAME.each do |codepoint, name|
          result[name] ||= codepoint # Only set first occurrence
        end
        result.freeze
      end

      # Get glyph name for Unicode codepoint
      #
      # @param codepoint [Integer] Unicode codepoint
      # @return [String] Glyph name from AGL, or uniXXXX format if not found
      def self.glyph_name_for_unicode(codepoint)
        UNICODE_TO_NAME[codepoint] || generate_uni_name(codepoint)
      end

      # Get Unicode codepoint for glyph name
      #
      # @param name [String] Glyph name
      # @return [Integer, nil] Unicode codepoint or nil if not found
      def self.unicode_for_glyph_name(name)
        # Try direct lookup
        code = NAME_TO_UNICODE[name]
        return code if code

        # Try parsing uniXXXX or uXXXXX format
        parse_uni_name(name)
      end

      # Check if a glyph name is in the AGL
      #
      # @param name [String] Glyph name
      # @return [Boolean] True if name is in AGL
      def self.agl_include?(name)
        NAME_TO_UNICODE.key?(name)
      end

      # Generate uniXXXX name for codepoint not in AGL
      #
      # @param codepoint [Integer] Unicode codepoint
      # @return [String] uniXXXX name
      def self.generate_uni_name(codepoint)
        format("uni%04X", codepoint)
      end

      # Parse uniXXXX or uXXXXX glyph name
      #
      # @param name [String] Glyph name in uni/u format
      # @return [Integer, nil] Unicode codepoint or nil if not a uni name
      def self.parse_uni_name(name)
        if name =~ /^uni([0-9A-Fa-f]{4})$/
          $1.to_i(16)
        elsif name =~ /^u([0-9A-Fa-f]+)$/
          $1.to_i(16)
        end
      end

      # Get all AGL glyph names
      #
      # @return [Array<String>] All glyph names in the AGL subset
      def self.all_glyph_names
        NAME_TO_UNICODE.keys.sort
      end

      # Get all Unicode codepoints in AGL
      #
      # @return [Array<Integer>] All Unicode codepoints in the AGL subset
      def self.all_codepoints
        UNICODE_TO_NAME.keys.sort
      end
    end
  end
end
