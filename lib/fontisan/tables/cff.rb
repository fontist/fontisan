# frozen_string_literal: true

require "stringio"

module Fontisan
  module Tables
    # CFF (Compact Font Format) table parser
    #
    # The CFF table contains PostScript-based glyph outline data for OpenType
    # fonts with CFF outlines (as opposed to TrueType glyf/loca outlines).
    # CFF is identified by the 'OTTO' signature in the font's sfnt version.
    #
    # CFF Table Structure:
    # ```
    # CFF Table = Header
    #           + Name INDEX
    #           + Top DICT INDEX
    #           + String INDEX
    #           + Global Subr INDEX
    #           + [Encodings]
    #           + [Charsets]
    #           + [FDSelect]
    #           + [CharStrings INDEX]
    #           + [Font DICT INDEX]
    #           + [Private DICT]
    #           + [Local Subr INDEX]
    # ```
    #
    # This implementation focuses on the foundational structures (Header and
    # INDEX) which are used throughout CFF. Additional structures like DICT,
    # CharStrings, Charset, and Encoding require separate implementations.
    #
    # Reference: Adobe CFF specification
    # https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
    #
    # Reference: docs/ttfunk-feature-analysis.md lines 2607-2648
    #
    # @example Reading a CFF table
    #   data = font.table_data['CFF ']
    #   cff = Fontisan::Tables::Cff.read(data)
    #   puts cff.font_count  # => 1
    #   puts cff.header.version  # => "1.0"
    class Cff < Binary::BaseRecord
      # Inner namespace autoloads — declared here so Cff::* constants
      # resolve on first reference without require_relative.
      autoload :CFFGlyph, "fontisan/tables/cff/cff_glyph"
      autoload :Charset, "fontisan/tables/cff/charset"
      autoload :CharString, "fontisan/tables/cff/charstring"
      autoload :CharStringBuilder, "fontisan/tables/cff/charstring_builder"
      autoload :Cff2CharStringBuilder,
               "fontisan/tables/cff/cff2_charstring_builder"
      autoload :CharStringParser, "fontisan/tables/cff/charstring_parser"
      autoload :CharStringRebuilder, "fontisan/tables/cff/charstring_rebuilder"
      autoload :CharstringsIndex, "fontisan/tables/cff/charstrings_index"
      autoload :Dict, "fontisan/tables/cff/dict"
      autoload :DictBuilder, "fontisan/tables/cff/dict_builder"
      autoload :Encoding, "fontisan/tables/cff/encoding"
      autoload :Header, "fontisan/tables/cff/header"
      autoload :HintOperationInjector,
               "fontisan/tables/cff/hint_operation_injector"
      autoload :Index, "fontisan/tables/cff/index"
      autoload :IndexBuilder, "fontisan/tables/cff/index_builder"
      autoload :OffsetRecalculator, "fontisan/tables/cff/offset_recalculator"
      autoload :PrivateDict, "fontisan/tables/cff/private_dict"
      autoload :PrivateDictWriter, "fontisan/tables/cff/private_dict_writer"
      autoload :TableBuilder, "fontisan/tables/cff/table_builder"
      autoload :TopDict, "fontisan/tables/cff/top_dict"

      # OpenType table tag for CFF
      TAG = "CFF "

      # @return [Cff::Header] CFF header structure
      attr_reader :header

      # @return [Cff::Index] Name INDEX containing font names
      attr_reader :name_index

      # @return [Cff::Index] Top DICT INDEX containing font-level data
      attr_reader :top_dict_index

      # @return [Array<TopDict>] Parsed Top DICT objects
      attr_reader :top_dicts

      # @return [Cff::Index] String INDEX containing string data
      attr_reader :string_index

      # @return [Cff::Index] Global Subr INDEX containing global subroutines
      attr_reader :global_subr_index

      # @return [String] Raw binary data for the entire CFF table
      attr_reader :raw_data

      # Override read to parse CFF structure
      #
      # @param io [IO, String] Binary data to read
      # @return [Cff] Parsed CFF table
      def self.read(io)
        cff = new
        return cff if io.nil?

        data = io.is_a?(String) ? io : io.read
        cff.parse!(data)
        cff
      end

      # Parse the CFF table structure
      #
      # This parses the foundational CFF structures: Header, Name INDEX,
      # Top DICT INDEX, String INDEX, and Global Subr INDEX.
      #
      # Additional structures (CharStrings, Charset, Encoding, Private DICT)
      # will be implemented in follow-up tasks.
      #
      # @param data [String] Binary data for the CFF table
      # @raise [CorruptedTableError] If CFF structure is invalid
      def parse!(data)
        @raw_data = data
        io = StringIO.new(data)

        # Parse CFF Header (4 bytes minimum)
        @header = Cff::Header.read(io)
        @header.validate!

        # Skip any additional header bytes beyond the standard 4
        # (hdr_size can be larger for extensions)
        if @header.hdr_size > 4
          io.seek(@header.hdr_size)
        end

        # Parse Name INDEX
        # Contains PostScript names of fonts in this CFF
        # Typically just one name for single-font CFF
        name_start = io.pos
        @name_index = Cff::Index.new(io, start_offset: name_start)

        # Validate that we have at least one font
        if @name_index.count.zero?
          raise CorruptedTableError, "CFF table must contain at least one font"
        end

        # Parse Top DICT INDEX
        # Contains font-level DICTs with metadata and pointers
        # Count should match name_index count (one DICT per font)
        top_dict_start = io.pos
        @top_dict_index = Cff::Index.new(io, start_offset: top_dict_start)

        # Validate Top DICT count matches Name count
        unless @top_dict_index.count == @name_index.count
          raise CorruptedTableError,
                "Top DICT count (#{@top_dict_index.count}) " \
                "must match Name count (#{@name_index.count})"
        end

        # Parse String INDEX
        # Contains additional string data beyond standard strings
        # Standard strings (SIDs 0-390) are built-in
        string_start = io.pos
        @string_index = Cff::Index.new(io, start_offset: string_start)

        # Parse Global Subr INDEX
        # Contains subroutines used across all fonts in CFF
        # Can be empty (count = 0)
        global_subr_start = io.pos
        @global_subr_index = Cff::Index.new(io, start_offset: global_subr_start)

        # Parse Top DICTs
        @top_dicts = []
        @top_dict_index.each do |dict_data|
          @top_dicts << TopDict.new(dict_data)
        end

        # Additional parsing will be added in follow-up tasks:
        # - Charset parsing
        # - Encoding parsing
        # - CharStrings parsing
        # - FDSelect parsing (for CIDFonts)
        # - Private DICT parsing (requires Top DICT offsets)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse CFF table: #{e.message}"
      end

      # Get the number of fonts in this CFF table
      #
      # Typically 1 for most OpenType fonts, but CFF supports multiple fonts
      #
      # @return [Integer] Number of fonts
      def font_count
        @name_index&.count || 0
      end

      # Get the PostScript name of a font by index
      #
      # @param index [Integer] Font index (0-based)
      # @return [String, nil] PostScript font name, or nil if invalid index
      def font_name(index = 0)
        name_data = @name_index[index]
        return nil unless name_data

        # Font names in Name INDEX are ASCII strings
        name_data.force_encoding("ASCII-8BIT")
      end

      # Get all font names in this CFF
      #
      # @return [Array<String>] Array of PostScript font names
      def font_names
        @name_index.to_a.map { |name| name.force_encoding("ASCII-8BIT") }
      end

      # Check if this is a CFF2 table (variable CFF)
      #
      # @return [Boolean] True if CFF version 2
      def cff2?
        @header&.cff2? || false
      end

      # Check if this is a standard CFF table (non-variable)
      #
      # @return [Boolean] True if CFF version 1
      def cff?
        @header&.cff? || false
      end

      # Get the CFF version string
      #
      # @return [String] Version in "major.minor" format
      def version
        @header&.version || "unknown"
      end

      # Get a string by String ID (SID)
      #
      # CFF has 391 predefined standard strings (SIDs 0-390).
      # Additional strings are stored in the String INDEX.
      #
      # @param sid [Integer] String ID
      # @return [String, nil] String data, or nil if invalid SID
      def string_for_sid(sid)
        # Standard strings (SIDs 0-390) are predefined
        # See CFF spec Appendix A for the complete list
        if sid <= 390
          standard_string(sid)
        else
          # Custom strings start at SID 391
          string_index_offset = sid - 391
          string_data = @string_index[string_index_offset]
          string_data&.force_encoding("ASCII-8BIT")
        end
      end

      # Get count of custom strings (beyond standard strings)
      #
      # @return [Integer] Number of custom strings
      def custom_string_count
        @string_index&.count || 0
      end

      # Get count of global subroutines
      #
      # @return [Integer] Number of global subroutines
      def global_subr_count
        @global_subr_index&.count || 0
      end

      # Get the Top DICT for a specific font
      #
      # @param index [Integer] Font index (0-based)
      # @return [TopDict, nil] Top DICT object, or nil if invalid index
      def top_dict(index = 0)
        @top_dicts&.[](index)
      end

      # Parse the Private DICT for a specific font
      #
      # The Private DICT location is specified in the Top DICT
      #
      # @param index [Integer] Font index (0-based)
      # @return [PrivateDict, nil] Private DICT object, or nil if not present
      def private_dict(index = 0)
        top = top_dict(index)
        return nil unless top

        private_info = top.private
        return nil unless private_info

        size, offset = private_info
        return nil if size <= 0 || offset.negative?

        # Extract Private DICT data from raw CFF data
        private_data = @raw_data[offset, size]
        return nil unless private_data

        PrivateDict.new(private_data)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse Private DICT: #{e.message}"
      end

      # Get the Local Subr INDEX for a specific font
      #
      # Local subroutines are stored in the Private DICT area
      #
      # @param index [Integer] Font index (0-based)
      # @return [Index, nil] Local Subr INDEX, or nil if not present
      def local_subrs(index = 0)
        priv_dict = private_dict(index)
        return nil unless priv_dict

        subrs_offset = priv_dict.subrs
        return nil unless subrs_offset

        top = top_dict(index)
        return nil unless top

        private_info = top.private
        return nil unless private_info

        _size, private_offset = private_info

        # Local Subr offset is relative to Private DICT start
        absolute_offset = private_offset + subrs_offset

        io = StringIO.new(@raw_data)
        io.seek(absolute_offset)
        Index.new(io, start_offset: absolute_offset)
      rescue StandardError => e
        raise CorruptedTableError,
              "Failed to parse Local Subr INDEX: #{e.message}"
      end

      # Get the CharStrings INDEX for a specific font
      #
      # The CharStrings INDEX contains glyph outline programs
      #
      # @param index [Integer] Font index (0-based)
      # @return [CharstringsIndex, nil] CharStrings INDEX, or nil if not
      #   present
      def charstrings_index(index = 0)
        top = top_dict(index)
        return nil unless top

        charstrings_offset = top.charstrings
        return nil unless charstrings_offset

        io = StringIO.new(@raw_data)
        io.seek(charstrings_offset)
        CharstringsIndex.new(io, start_offset: charstrings_offset)
      rescue StandardError => e
        raise CorruptedTableError,
              "Failed to parse CharStrings INDEX: #{e.message}"
      end

      # Get a CharString for a specific glyph
      #
      # This returns an interpreted CharString object with the glyph's
      # outline data
      #
      # @param glyph_index [Integer] Glyph index (0-based, 0 is typically
      #   .notdef)
      # @param font_index [Integer] Font index in CFF (default 0)
      # @return [CharString, nil] Interpreted CharString, or nil if not found
      #
      # @example Getting a glyph's CharString
      #   cff = Fontisan::Tables::Cff.read(data)
      #   charstring = cff.charstring_for_glyph(42)
      #   puts charstring.width
      #   puts charstring.bounding_box
      #   charstring.to_commands.each { |cmd| puts cmd.inspect }
      def charstring_for_glyph(glyph_index, font_index = 0)
        charstrings = charstrings_index(font_index)
        return nil unless charstrings

        priv_dict = private_dict(font_index)
        return nil unless priv_dict

        local_subr_index = local_subrs(font_index)

        charstrings.charstring_at(
          glyph_index,
          priv_dict,
          @global_subr_index,
          local_subr_index,
        )
      rescue StandardError => e
        raise CorruptedTableError,
              "Failed to get CharString for glyph #{glyph_index}: #{e.message}"
      end

      # Get the number of glyphs in a font
      #
      # @param index [Integer] Font index (0-based)
      # @return [Integer] Number of glyphs, or 0 if CharStrings not available
      def glyph_count(index = 0)
        charstrings = charstrings_index(index)
        charstrings&.glyph_count || 0
      end

      # Validate the CFF table structure
      #
      # @return [Boolean] True if valid
      def valid?
        return false unless @header&.valid?
        return false unless @name_index&.count&.positive?
        return false unless @top_dict_index
        return false unless @top_dict_index.count == @name_index.count
        return false unless @string_index
        return false unless @global_subr_index

        true
      end

      # Adobe Standard Encoding glyph names that map 1:1 to CFF SIDs
      # 0..390. Source: Adobe CFF Specification 1.0 (TN 5176), Appendix A.
      # These cover the full standard string table: printable ASCII,
      # ligatures, currency, Cyrillic (afii*), and Unicode-mapped names.
      STANDARD_STRINGS = [
        ".notdef", # SID 0
        "space", # SID 1 (code 32)
        "exclam", # SID 2 (code 33)
        "quotedbl", # SID 3 (code 34)
        "numbersign", # SID 4 (code 35)
        "dollar", # SID 5 (code 36)
        "percent", # SID 6 (code 37)
        "ampersand", # SID 7 (code 38)
        "quoteright", # SID 8 (code 39)
        "parenleft", # SID 9 (code 40)
        "parenright", # SID 10 (code 41)
        "asterisk", # SID 11 (code 42)
        "plus", # SID 12 (code 43)
        "comma", # SID 13 (code 44)
        "hyphen", # SID 14 (code 45)
        "period", # SID 15 (code 46)
        "slash", # SID 16 (code 47)
        "zero", # SID 17 (code 48)
        "one", # SID 18 (code 49)
        "two", # SID 19 (code 50)
        "three", # SID 20 (code 51)
        "four", # SID 21 (code 52)
        "five", # SID 22 (code 53)
        "six", # SID 23 (code 54)
        "seven", # SID 24 (code 55)
        "eight", # SID 25 (code 56)
        "nine", # SID 26 (code 57)
        "colon", # SID 27 (code 58)
        "semicolon", # SID 28 (code 59)
        "less", # SID 29 (code 60)
        "equal", # SID 30 (code 61)
        "greater", # SID 31 (code 62)
        "question", # SID 32 (code 63)
        "at", # SID 33 (code 64)
        "A", # SID 34 (code 65)
        "B", # SID 35 (code 66)
        "C", # SID 36 (code 67)
        "D", # SID 37 (code 68)
        "E", # SID 38 (code 69)
        "F", # SID 39 (code 70)
        "G", # SID 40 (code 71)
        "H", # SID 41 (code 72)
        "I", # SID 42 (code 73)
        "J", # SID 43 (code 74)
        "K", # SID 44 (code 75)
        "L", # SID 45 (code 76)
        "M", # SID 46 (code 77)
        "N", # SID 47 (code 78)
        "O", # SID 48 (code 79)
        "P", # SID 49 (code 80)
        "Q", # SID 50 (code 81)
        "R", # SID 51 (code 82)
        "S", # SID 52 (code 83)
        "T", # SID 53 (code 84)
        "U", # SID 54 (code 85)
        "V", # SID 55 (code 86)
        "W", # SID 56 (code 87)
        "X", # SID 57 (code 88)
        "Y", # SID 58 (code 89)
        "Z", # SID 59 (code 90)
        "bracketleft", # SID 60 (code 91)
        "backslash", # SID 61 (code 92)
        "bracketright", # SID 62 (code 93)
        "asciicircum", # SID 63 (code 94)
        "underscore", # SID 64 (code 95)
        "quoteleft", # SID 65 (code 96)
        "a", # SID 66 (code 97)
        "b", # SID 67 (code 98)
        "c", # SID 68 (code 99)
        "d", # SID 69 (code 100)
        "e", # SID 70 (code 101)
        "f", # SID 71 (code 102)
        "g", # SID 72 (code 103)
        "h", # SID 73 (code 104)
        "i", # SID 74 (code 105)
        "j", # SID 75 (code 106)
        "k", # SID 76 (code 107)
        "l", # SID 77 (code 108)
        "m", # SID 78 (code 109)
        "n", # SID 79 (code 110)
        "o", # SID 80 (code 111)
        "p", # SID 81 (code 112)
        "q", # SID 82 (code 113)
        "r", # SID 83 (code 114)
        "s", # SID 84 (code 115)
        "t", # SID 85 (code 116)
        "u", # SID 86 (code 117)
        "v", # SID 87 (code 118)
        "w", # SID 88 (code 119)
        "x", # SID 89 (code 120)
        "y", # SID 90 (code 121)
        "z", # SID 91 (code 122)
        "braceleft", # SID 92 (code 123)
        "bar", # SID 93 (code 124)
        "braceright", # SID 94 (code 125)
        "asciitilde", # SID 95 (code 126)
        "exclamdown", # SID 96
        "cent", # SID 97
        "sterling", # SID 98
        "fraction", # SID 99
        "yen", # SID 100
        "florin", # SID 101
        "section", # SID 102
        "currency", # SID 103
        "quotesingle", # SID 104
        "quotedblleft", # SID 105
        "guillemotleft", # SID 106
        "guilsinglleft", # SID 107
        "guilsinglright", # SID 108
        "fi", # SID 109
        "fl", # SID 110
        "endash", # SID 111
        "dagger", # SID 112
        "daggerdbl", # SID 113
        "periodcentered", # SID 114
        "paragraph", # SID 115
        "bullet", # SID 116
        "quotesinglbase", # SID 117
        "quotedblbase", # SID 118
        "quotedblright", # SID 119
        "guillemotright", # SID 120
        "ellipsis", # SID 121
        "perthousand", # SID 122
        "questiondown", # SID 123
        "grave", # SID 124
        "acute", # SID 125
        "circumflex", # SID 126
        "tilde", # SID 127
        "macron", # SID 128
        "breve", # SID 129
        "dotaccent", # SID 130
        "dieresis", # SID 131
        "ring", # SID 132
        "cedilla", # SID 133
        "hungarumlaut", # SID 134
        "ogonek", # SID 135
        "caron", # SID 136
        "emdash", # SID 137
        "AE", # SID 138
        "ordfeminine", # SID 139
        "Lslash", # SID 140
        "Oslash", # SID 141
        "OE", # SID 142
        "ordmasculine", # SID 143
        "ae", # SID 144
        "dotlessi", # SID 145
        "lslash", # SID 146
        "oslash", # SID 147
        "oe", # SID 148
        "germandbls", # SID 149
        "onesuperior", # SID 150
        "twosuperior", # SID 151
        "threesuperior", # SID 152
        "minus", # SID 153
        "multiply", # SID 154
        "onesuperior", # SID 155 — oneshalf (fraction)
        "onequarter", # SID 156
        "threequarters", # SID 157
        "questiondownsmall", # SID 158
        "exclamdownsmall", # SID 159
        "capitalshadow", # SID 160
        "asciicircumsmall", # SID 161
        "centinferior", # SID 162
        "sterlinginferior", # SID 163
        "fractionsmall", # SID 164
        "zerosuperior", # SID 165
        "yeninferior", # SID 166
        "florinsmall", # SID 167
        "dieresissmall", # SID 168
        "caronsmall", # SID 169
        "commaaccent", # SID 170
        "dotlessj", # SID 171
        "ae", # SID 172 — ae small (accent variant)
        "hoi", # SID 173 — hookabove (short form)
        "circumflexsmall", # SID 174
        "tildesmall", # SID 175
        "macronsmall", # SID 176
        "brevesmall", # SID 177
        "dotaccentsmall", # SID 178
        "slash", # SID 179
        "ringsmall", # SID 180
        "cedillasmall", # SID 181
        "hungarumlautsmall", # SID 182
        "ogoneksmall", # SID 183
        "ringsmall", # SID 184
        "fismall", # SID 185
        "flsmall", # SID 186
        "Acutesmall", # SID 187
        "Hungarumlautsmall", # SID 188
        "Caronsmall", # SID 189
        "Cedillasmall", # SID 190
        "Brevesmall", # SID 191
        "Macronsmall", # SID 192
        "Dieresissmall", # SID 193
        "Ogoneksmall", # SID 194
        "Circumflexsmall", # SID 195
        "Tildesmall", # SID 196
        "Ringsmall", # SID 197
        "Gravesmall", # SID 198
        "Lslashsmall", # SID 199
        "OEsmall", # SID 200
        "florin", # SID 201 — florin small variant
        "y", # SID 202 — y small variant
        "z", # SID 203 — z small variant
        "commasuperior", # SID 204
        "figuredash", # SID 205
        "hookleft", # SID 206
        "afii00208", # SID 207
        "afii10017", # SID 208
        "afii10018", # SID 209
        "afii10019", # SID 210
        "afii10020", # SID 211
        "afii10021", # SID 212
        "afii10022", # SID 213
        "afii10023", # SID 214
        "afii10024", # SID 215
        "afii10025", # SID 216
        "afii10026", # SID 217
        "afii10027", # SID 218
        "afii10028", # SID 219
        "afii10029", # SID 220
        "afii10030", # SID 221
        "afii10031", # SID 222
        "afii10032", # SID 223
        "afii10033", # SID 224
        "afii10034", # SID 225
        "afii10035", # SID 226
        "afii10036", # SID 227
        "afii10037", # SID 228
        "afii10038", # SID 229
        "afii10039", # SID 230
        "afii10040", # SID 231
        "afii10041", # SID 232
        "afii10042", # SID 233
        "afii10043", # SID 234
        "afii10044", # SID 235
        "afii10045", # SID 236
        "afii10046", # SID 237
        "afii10047", # SID 238
        "afii10048", # SID 239
        "afii10049", # SID 240
        "afii10065", # SID 241
        "afii10066", # SID 242
        "afii10067", # SID 243
        "afii10068", # SID 244
        "afii10069", # SID 245
        "afii10070", # SID 246
        "afii10071", # SID 247
        "afii10072", # SID 248
        "afii10073", # SID 249
        "afii10074", # SID 250
        "afii10075", # SID 251
        "afii10076", # SID 252
        "afii10077", # SID 253
        "afii10078", # SID 254
        "afii10079", # SID 255
        "afii10080", # SID 256
        "afii10081", # SID 257
        "afii10082", # SID 258
        "afii10083", # SID 259
        "afii10084", # SID 260
        "afii10085", # SID 261
        "afii10086", # SID 262
        "afii10087", # SID 263
        "afii10088", # SID 264
        "afii10089", # SID 265
        "afii10090", # SID 266
        "afii10091", # SID 267
        "afii10092", # SID 268
        "afii10093", # SID 269
        "afii10094", # SID 270
        "afii10095", # SID 271
        "afii10096", # SID 272
        "afii10097", # SID 273
        "afii10071.alt", # SID 274
        "afii10061.alt", # SID 275
        "afii10101", # SID 276
        "afii10102", # SID 277
        "afii10103", # SID 278
        "afii10104", # SID 279
        "afii10105", # SID 280
        "afii10106", # SID 281
        "afii10107", # SID 282
        "afii10108", # SID 283
        "afii10109", # SID 284
        "section.alt", # SID 285
        "afii10110", # SID 286
        "afii10193", # SID 287
        "afii10194", # SID 288
        "afii10195", # SID 289
        "afii10196", # SID 290
        "afii10050", # SID 291
        "afii10098", # SID 292
        "afii10024.alt", # SID 293
        "afii10050.alt", # SID 294
        "Wgrave", # SID 295
        "Wacute", # SID 296
        "Wdieresis", # SID 297
        "Ygrave", # SID 298
        "afii10051", # SID 299
        "afii10052", # SID 300
        "afii10053", # SID 301
        "afii10054", # SID 302
        "afii10055", # SID 303
        "afii10056", # SID 304
        "afii10057", # SID 305
        "afii10058", # SID 306
        "afii10059", # SID 307
        "afii10060", # SID 308
        "afii10061", # SID 309
        "afii10146.alt", # SID 310
        "afii10031.alt", # SID 311
        "afii10147.alt", # SID 312
        "afii10146", # SID 313
        "afii10147", # SID 314
        "afii10148", # SID 315
        "afii10192", # SID 316
        "afii10846", # SID 317
        "afii57799", # SID 318
        "afii57801", # SID 319
        "afii57800", # SID 320
        "afii57802", # SID 321
        "afii57803", # SID 322
        "afii57804", # SID 323
        "afii57805", # SID 324
        "afii57806", # SID 325
        "afii57807", # SID 326
        "afii57808", # SID 327
        "afii57809", # SID 328
        "afii57810", # SID 329
        "afii57811", # SID 330
        "afii57812", # SID 331
        "afii57813", # SID 332
        "afii57814", # SID 333
        "afii57815", # SID 334
        "afii57816", # SID 335
        "afii57817", # SID 336
        "afii57818", # SID 337
        "afii57388", # SID 338
        "afii57403", # SID 339
        "afii57407", # SID 340
        "afii57409", # SID 341
        "afii57410", # SID 342
        "afii57411", # SID 343
        "afii57412", # SID 344
        "afii57413", # SID 345
        "afii57414", # SID 346
        "afii57415", # SID 347
        "afii57416", # SID 348
        "afii57417", # SID 349
        "afii57418", # SID 350
        "afii57419", # SID 351
        "afii57420", # SID 352
        "afii57421", # SID 353
        "afii57422", # SID 354
        "afii57423", # SID 355
        "afii57424", # SID 356
        "afii57425", # SID 357
        "afii57426", # SID 358
        "afii57427", # SID 359
        "afii57428", # SID 360
        "afii57429", # SID 361
        "afii57430", # SID 362
        "afii57431", # SID 363
        "afii57432", # SID 364
        "afii57433", # SID 365
        "afii57434", # SID 366
        "Afii61264", # SID 367
        "Afii61265", # SID 368
        "Afii61266", # SID 369
        "afii63167", # SID 370
        "afii57511", # SID 371
        "afii57512", # SID 372
        "afii57513", # SID 373
        "afii57514", # SID 374
        "afii57515", # SID 375
        "afii57516", # SID 376
        "afii57517", # SID 377
        "afii57518", # SID 378
        "afii57519", # SID 379
        "afii57520", # SID 380
        "afii57521", # SID 381
        "afii64237", # SID 382
        "afii64238", # SID 383
        "exclamdouble", # SID 384
        "uni204A", # SID 385
        "uni2080", # SID 386
        "uni2081", # SID 387
        "uni2082", # SID 388
        "uni2083", # SID 389
        "uni2084", # SID 390
      ].freeze

      # Total count of standard CFF strings (SID 0-390 per Adobe
      # CFF spec Appendix A). Used to validate that the array length
      # matches the spec.
      STANDARD_STRING_COUNT = 391

      private

      # Get a standard CFF string by SID (0-390).
      #
      # Full 391-entry standard string table per Adobe CFF spec
      # Appendix A. Returns nil for SID < 0 or SID > 390.
      #
      # @param sid [Integer] String ID (0-390)
      # @return [String, nil] standard string, or nil for out-of-range SIDs
      def standard_string(sid)
        return nil if sid.negative?

        STANDARD_STRINGS[sid]
      end

      # Get the Charset for a specific font
      #
      # Charset maps glyph IDs to glyph names via String IDs
      #
      # @param index [Integer] Font index (0-based)
      # @return [Charset, nil] Charset object, or nil if not present
      def charset(index = 0)
        top = top_dict(index)
        return nil unless top

        charset_offset = top.charset
        return nil unless charset_offset

        # Handle predefined charsets
        if charset_offset <= 2
          num_glyphs = glyph_count(index)
          return Charset.new(charset_offset, num_glyphs, self)
        end

        # Parse custom charset from offset
        charset_data = @raw_data[charset_offset..]
        return nil unless charset_data

        num_glyphs = glyph_count(index)
        Charset.new(charset_data, num_glyphs, self)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse Charset: #{e.message}"
      end

      # Get the Encoding for a specific font
      #
      # Encoding maps character codes to glyph IDs
      #
      # @param index [Integer] Font index (0-based)
      # @return [Encoding, nil] Encoding object, or nil if not present
      def encoding(index = 0)
        top = top_dict(index)
        return nil unless top

        encoding_offset = top.encoding
        return nil unless encoding_offset

        # Handle predefined encodings
        if encoding_offset <= 1
          num_glyphs = glyph_count(index)
          return Encoding.new(encoding_offset, num_glyphs)
        end

        # Parse custom encoding from offset
        encoding_data = @raw_data[encoding_offset..]
        return nil unless encoding_data

        num_glyphs = glyph_count(index)
        Encoding.new(encoding_data, num_glyphs)
      rescue StandardError => e
        raise CorruptedTableError, "Failed to parse Encoding: #{e.message}"
      end
    end
  end
end
