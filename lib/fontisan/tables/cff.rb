# frozen_string_literal: true

require "stringio"
require_relative "../binary/base_record"

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
        warn "Failed to parse Private DICT: #{e.message}"
        nil
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
        warn "Failed to parse Local Subr INDEX: #{e.message}"
        nil
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
        warn "Failed to parse CharStrings INDEX: #{e.message}"
        nil
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
        warn "Failed to get CharString for glyph #{glyph_index}: #{e.message}"
        nil
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

      private

      # Get a standard CFF string by SID
      #
      # This is a placeholder that returns a generic string.
      # A complete implementation would include all 391 standard strings
      # from CFF spec Appendix A.
      #
      # TODO: Implement complete standard string table in follow-up task
      #
      # @param sid [Integer] String ID (0-390)
      # @return [String] Standard string
      def standard_string(sid)
        # Placeholder implementation
        # Full implementation should include all standard strings
        # from CFF specification Appendix A
        case sid
        when 0 then ".notdef"
        when 1 then "space"
        when 2 then "exclam"
        # ... (388 more standard strings)
        else
          ".notdef" # Fallback
        end
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
        warn "Failed to parse Charset: #{e.message}"
        nil
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
        warn "Failed to parse Encoding: #{e.message}"
        nil
      end
    end

    # Load nested class definitions after the main class is defined
    require_relative "cff/header"
    require_relative "cff/index"
    require_relative "cff/dict"
    require_relative "cff/top_dict"
    require_relative "cff/private_dict"
    require_relative "cff/charstring"
    require_relative "cff/charstrings_index"
    require_relative "cff/charset"
    require_relative "cff/encoding"
    require_relative "cff/cff_glyph"
  end
end
