# frozen_string_literal: true

require_relative "../type1/charstring_converter"
require_relative "../type1/font_dictionary"
require_relative "../type1/charstrings"
require_relative "../type1_font"
require_relative "cff_table_builder"

module Fontisan
  module Converters
    # Converter for Adobe Type 1 fonts to/from SFNT formats.
    #
    # [`Type1Converter`](lib/fontisan/converters/type1_converter.rb) handles
    # bidirectional conversion between Type 1 fonts (PFB/PFA) and SFNT-based
    # formats (TTF, OTF, WOFF, WOFF2).
    #
    # == Conversion Strategy
    #
    # Type 1 fonts use PostScript CharStrings that are similar to CFF CharStrings
    # used in OpenType fonts. The conversion uses CharStringConverter for the
    # CharString translation.
    #
    # * Type 1 → OTF: Convert Type 1 CharStrings to CFF format, build CFF table
    # * OTF → Type 1: Convert CFF CharStrings to Type 1 format, build PFB/PFA
    # * Type 1 → TTF: Type 1 → OTF → TTF (via OutlineConverter)
    # * TTF → Type 1: TTF → OTF → Type 1
    #
    # == Limitations
    #
    # * seac composite glyphs are expanded to base glyphs (placeholder implemented)
    # * Some Type 1 hints may not be preserved accurately
    # * Unique Type 1 features like Flex operators are not converted
    #
    # @example Convert Type 1 to OTF
    #   font = FontLoader.load("font.pfb")
    #   converter = Type1Converter.new
    #   tables = converter.convert(font, target_format: :otf)
    #
    # @example Convert OTF to Type 1
    #   font = FontLoader.load("font.otf")
    #   converter = Type1Converter.new
    #   tables = converter.convert(font, target_format: :type1)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    # @see CharStringConverter
    class Type1Converter
      include ConversionStrategy
      include CffTableBuilder

      # Initialize a new Type1Converter
      #
      # @param options [Hash] Converter options
      # @option options [Boolean] :optimize_cff Enable CFF optimization (default: false)
      # @option options [Boolean] :preserve_hints Preserve hinting (default: true)
      # @option options [Symbol] :target_format Target format for conversion
      def initialize(options = {})
        @optimize_cff = options.fetch(:optimize_cff, false)
        @preserve_hints = options.fetch(:preserve_hints, true)
        @target_format = options[:target_format]
      end

      # Convert font to target format
      #
      # @param font [Type1Font, OpenTypeFont, TrueTypeFont] Source font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Map of table tags to binary data
      def convert(font, options = {})
        target_format = options[:target_format] || @target_format ||
          detect_target_format(font)
        validate(font, target_format)

        source_format = detect_format(font)

        case [source_format, target_format]
        when %i[type1 otf]
          convert_type1_to_otf(font, options)
        when %i[otf type1]
          convert_otf_to_type1(font)
        when %i[type1 ttf]
          convert_type1_to_ttf(font, options)
        when %i[ttf type1]
          convert_ttf_to_type1(font)
        else
          raise Fontisan::Error,
                "Unsupported conversion: #{source_format} → #{target_format}"
        end
      end

      # Get supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[type1 otf],
          %i[otf type1],
          %i[type1 ttf],
          %i[ttf type1],
        ]
      end

      # Validate font for conversion
      #
      # @param font [Type1Font, OpenTypeFont, TrueTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If font is invalid
      # @raise [Error] If conversion is not supported
      def validate(font, target_format)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:font_dictionary) || font.respond_to?(:tables)
          raise ArgumentError,
                "Font must be Type1Font or have :tables method"
        end

        source_format = detect_format(font)
        unless supports?(source_format, target_format)
          raise Fontisan::Error,
                "Conversion #{source_format} → #{target_format} not supported"
        end

        true
      end

      private

      # Detect font format
      #
      # @param font [Type1Font, OpenTypeFont, TrueTypeFont] Font to detect
      # @return [Symbol] Font format (:type1, :ttf, :otf)
      def detect_format(font)
        case font
        when Type1Font
          :type1
        when TrueTypeFont
          :ttf
        when OpenTypeFont
          :otf
        else
          # Try to detect from tables
          if font.respond_to?(:tables)
            if font.tables.key?("glyf")
              :ttf
            elsif font.tables.key?("CFF ") || font.tables.key?("CFF2")
              :otf
            else
              raise Fontisan::Error, "Cannot detect font format"
            end
          else
            raise Fontisan::Error, "Unknown font type: #{font.class}"
          end
        end
      end

      # Detect target format from font class or options
      #
      # @param font [Type1Font, OpenTypeFont, TrueTypeFont] Source font
      # @return [Symbol] Target format
      def detect_target_format(font)
        case font
        when Type1Font
          :otf # Default: Type 1 → OTF
        when TrueTypeFont
          :type1 # TTF → Type 1
        when OpenTypeFont
          :type1 # OTF → Type 1
        else
          :otf
        end
      end

      # Convert Type 1 font to OpenType/CFF
      #
      # @param font [Type1Font] Source Type 1 font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Target tables including CFF table
      def convert_type1_to_otf(font, _options = {})
        # Convert Type 1 CharStrings to CFF format
        converter = Type1::CharStringConverter.new(font.charstrings)
        cff_charstrings = {}

        font.charstrings.each_charstring do |glyph_name, charstring|
          cff_charstrings[glyph_name] = converter.convert(charstring)
        end

        # Build font dictionary for CFF
        font_dict = build_cff_font_dict(font)

        # Build private dictionary for CFF
        private_dict = build_cff_private_dict(font)

        # Build CFF table
        # Note: This is a simplified implementation
        # A full implementation would build proper CFF INDEX structures
        cff_data = build_cff_table_data(font, cff_charstrings, font_dict,
                                        private_dict)

        # Build other required SFNT tables
        tables = {}

        # Build head table
        tables["head"] = build_head_table(font)

        # Build hhea table
        tables["hhea"] = build_hhea_table(font)

        # Build maxp table
        tables["maxp"] = build_maxp_table(font)

        # Build name table
        tables["name"] = build_name_table(font)

        # Build OS/2 table
        tables["OS/2"] = build_os2_table(font)

        # Build post table
        tables["post"] = build_post_table(font)

        # Build cmap table
        tables["cmap"] = build_cmap_table(font)

        # Add CFF table
        tables["CFF "] = cff_data

        tables
      end

      # Convert OpenType/CFF font to Type 1
      #
      # @param font [OpenTypeFont] Source OpenType font
      # @return [Hash<String, String>] Type 1 font data as PFB
      def convert_otf_to_type1(font)
        # Extract CFF table
        cff_table = font.table("CFF ")
        raise Fontisan::Error, "CFF table not found" unless cff_table

        # Parse CFF table to extract CharStrings
        # Note: This is a simplified implementation
        # A full implementation would parse CFF INDEX structures

        # Convert CFF CharStrings to Type 1 format
        type1_charstrings = {}
        Type1::CharStringConverter.new

        # Extract glyph outlines from CFF
        # For each glyph, convert CFF CharString to Type 1
        font.outlines.each_with_index do |outline, index|
          glyph_name = font.glyph_name(index) || "glyph#{index}"
          # Reverse conversion: CFF → Type 1
          # This is a placeholder - full implementation requires CFF parser
          type1_charstrings[glyph_name] = convert_cff_to_type1(outline)
        end

        # Build Type 1 font data
        build_type1_data(font, type1_charstrings)
      end

      # Convert Type 1 font to TrueType (via OTF)
      #
      # @param font [Type1Font] Source Type 1 font
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Target tables including glyf table
      def convert_type1_to_ttf(font, options = {})
        # First convert to OTF
        otf_tables = convert_type1_to_otf(font, options)

        # Then use OutlineConverter to convert OTF to TTF
        # Create a temporary OTF font object
        temp_otf = OpenTypeFont.new
        otf_tables.each do |tag, data|
          temp_otf.tables[tag] = data
        end

        # Use OutlineConverter for OTF → TTF
        outline_converter = OutlineConverter.new(
          optimize_cff: @optimize_cff,
          preserve_hints: @preserve_hints,
          target_format: :ttf,
        )

        outline_converter.convert(temp_otf, target_format: :ttf)
      end

      # Convert TrueType font to Type 1 (via OTF)
      #
      # @param font [TrueTypeFont] Source TrueType font
      # @return [Hash<String, String>] Type 1 font data as PFB
      def convert_ttf_to_type1(font)
        # First use OutlineConverter to convert TTF to OTF
        outline_converter = OutlineConverter.new(
          optimize_cff: @optimize_cff,
          preserve_hints: @preserve_hints,
          target_format: :otf,
        )

        otf_tables = outline_converter.convert(font, target_format: :otf)

        # Create a temporary OTF font object
        temp_otf = OpenTypeFont.new
        otf_tables.each do |tag, data|
          temp_otf.tables[tag] = data
        end

        # Then convert OTF to Type 1
        convert_otf_to_type1(temp_otf)
      end

      # Build CFF font dictionary from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [Hash] CFF font dictionary data
      def build_cff_font_dict(font)
        {
          version: font.font_dictionary.version || "001.000",
          notice: font.font_dictionary.notice || "",
          copyright: font.font_dictionary.copyright || "",
          full_name: font.font_dictionary.full_name || font.font_name,
          family_name: font.font_dictionary.family_name || font.font_name,
          weight: font.font_dictionary.weight || "Medium",
          font_b_box: font.font_dictionary.font_bbox || [0, 0, 0, 0],
          font_matrix: font.font_dictionary.font_matrix || [0.001, 0, 0, 0.001,
                                                            0, 0],
          charset: font.charstrings.encoding.keys,
          encoding: font.charstrings.encoding,
        }
      end

      # Build CFF private dictionary from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [Hash] CFF private dictionary data
      def build_cff_private_dict(font)
        private_dict = font.private_dict
        {
          blue_values: private_dict.blue_values || [],
          other_blues: private_dict.other_blues || [],
          family_blues: private_dict.family_blues || [],
          family_other_blues: private_dict.family_other_blues || [],
          blue_scale: private_dict.blue_scale || 0.039625,
          blue_shift: private_dict.blue_shift || 7,
          blue_fuzz: private_dict.blue_fuzz || 1,
          std_hw: private_dict.std_hw || 0,
          std_vw: private_dict.std_vw || 0,
          stem_snap_h: private_dict.stem_snap_h || [],
          stem_snap_v: private_dict.stem_snap_v || [],
          force_bold: private_dict.force_bold || false,
          language_group: private_dict.language_group || 0,
          expansion_factor: private_dict.expansion_factor || 0.06,
          initial_random_seed: private_dict.initial_random_seed || 0,
        }
      end

      # Build CFF table data
      #
      # @param font [Type1Font] Source Type 1 font
      # @param charstrings [Hash] CFF CharStrings (glyph_name => data)
      # @param font_dict [Hash] CFF font dictionary (not used, kept for compatibility)
      # @param private_dict [Hash] CFF private dictionary (not used, kept for compatibility)
      # @return [String] CFF table binary data
      def build_cff_table_data(font, charstrings, _font_dict, _private_dict)
        # Convert charstrings hash to array (build_cff_table expects array)
        charstrings_array = charstrings.values

        # Build CFF table using CffTableBuilder
        # We need to pass the Type1Font as-is for metadata extraction
        build_cff_table(charstrings_array, [], font)
      end

      # Override extract_font_name to handle Type1Font
      #
      # @param font [Type1Font, TrueTypeFont, OpenTypeFont] Font
      # @return [String] Font name
      def extract_font_name(font)
        if font.is_a?(Type1Font)
          # Get font name from Type1Font
          name = font.font_name || font.font_dictionary&.font_name
          return name.dup.force_encoding("ASCII-8BIT") if name
        end

        # Fall back to original implementation for TrueTypeFont/OpenTypeFont
        super
      end

      # Convert CFF outline to Type 1 CharString
      #
      # @param outline [Outline] Glyph outline
      # @return [String] Type 1 CharString bytecode
      def convert_cff_to_type1(_outline)
        # Reverse conversion from CFF to Type 1
        # This is a placeholder implementation
        # Full implementation requires:
        # 1. Parse CFF CharString to commands
        # 2. Map CFF operators to Type 1 operators
        # 3. Encode numbers in Type 1 format
        # 4. Handle hints and subroutines

        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build Type 1 font data
      #
      # @param font [OpenTypeFont] Source OpenType font
      # @param charstrings [Hash] Type 1 CharStrings
      # @return [Hash] Type 1 font data with :pfb key
      def build_type1_data(_font, _charstrings)
        # Build PFB format
        # This is a placeholder implementation
        # Full implementation requires:
        # 1. Build Font Dictionary
        # 2. Build Private Dictionary
        # 3. Build CharStrings
        # 4. Encrypt with eexec
        # 5. Format as PFB chunks

        pfb_data = String.new(encoding: Encoding::ASCII_8BIT)

        { pfb: pfb_data }
      end

      # Build head table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] head table binary data
      def build_head_table(_font)
        # Placeholder: Build actual head table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build hhea table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] hhea table binary data
      def build_hhea_table(_font)
        # Placeholder: Build actual hhea table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build maxp table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] maxp table binary data
      def build_maxp_table(_font)
        # Placeholder: Build actual maxp table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build name table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] name table binary data
      def build_name_table(_font)
        # Placeholder: Build actual name table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build OS/2 table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] OS/2 table binary data
      def build_os2_table(_font)
        # Placeholder: Build actual OS/2 table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build post table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] post table binary data
      def build_post_table(_font)
        # Placeholder: Build actual post table
        String.new(encoding: Encoding::ASCII_8BIT)
      end

      # Build cmap table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] cmap table binary data
      def build_cmap_table(_font)
        # Placeholder: Build actual cmap table
        String.new(encoding: Encoding::ASCII_8BIT)
      end
    end
  end
end
