# frozen_string_literal: true

require_relative "../conversion_options"
require_relative "../type1/charstring_converter"
require_relative "../type1/cff_to_type1_converter"
require_relative "../type1/font_dictionary"
require_relative "../type1/charstrings"
require_relative "../type1/seac_expander"
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
    # == Conversion Options
    #
    # The converter accepts [`ConversionOptions`](../conversion_options) with
    # opening and generating options:
    #
    # * Opening options: decompose_composites, generate_unicode, read_all_records
    # * Generating options: decompose_on_output, hinting_mode, write_pfm, write_afm
    #
    # @example Convert Type 1 to OTF with options
    #   font = FontLoader.load("font.pfb")
    #   options = ConversionOptions.recommended(from: :type1, to: :otf)
    #   converter = Type1Converter.new
    #   tables = converter.convert(font, options: options)
    #
    # @example Convert with preset
    #   options = ConversionOptions.from_preset(:type1_to_modern)
    #   tables = converter.convert(font, options: options)
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
      # @param options [Hash, ConversionOptions] Conversion options
      # @option options [Symbol] :target_format Target format override
      # @option options [ConversionOptions] :options ConversionOptions object
      # @return [Hash<String, String>] Map of table tags to binary data
      def convert(font, options = {})
        # Extract ConversionOptions if provided
        conv_options = extract_conversion_options(options)

        target_format = options[:target_format] || conv_options&.to || @target_format ||
          detect_target_format(font)
        validate(font, target_format)

        # Apply opening options to source font
        apply_opening_options(font, conv_options) if conv_options

        source_format = detect_format(font)

        case [source_format, target_format]
        when %i[type1 otf]
          convert_type1_to_otf(font, conv_options)
        when %i[otf type1]
          convert_otf_to_type1(font, conv_options)
        when %i[type1 ttf]
          convert_type1_to_ttf(font, conv_options)
        when %i[ttf type1]
          convert_ttf_to_type1(font, conv_options)
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

      # Extract ConversionOptions from options hash
      #
      # @param options [Hash, ConversionOptions] Options or hash containing :options key
      # @return [ConversionOptions, nil] Extracted ConversionOptions or nil
      def extract_conversion_options(options)
        return options if options.is_a?(ConversionOptions)

        options[:options] if options.is_a?(Hash)
      end

      # Apply opening options to source font
      #
      # @param font [Type1Font] Source font
      # @param conv_options [ConversionOptions] Conversion options with opening options
      def apply_opening_options(font, conv_options)
        return unless font.is_a?(Type1Font)
        return unless conv_options

        # Generate Unicode codepoints if requested
        if conv_options.opening_option?(:generate_unicode)
          generate_unicode_mappings(font)
        end

        # Decompose seac composites if requested
        if conv_options.opening_option?(:decompose_composites)
          decompose_seac_glyphs(font)
        end

        # Read all font dictionary records if requested
        if conv_options.opening_option?(:read_all_records) && font.font_dictionary.respond_to?(:reload)
          # Ensure full font dictionary is loaded
          font.font_dictionary.reload
        end
      end

      # Generate Unicode codepoints from glyph names/encoding
      #
      # @param font [Type1Font] Source Type 1 font
      def generate_unicode_mappings(_font)
        # Placeholder: Generate Unicode mappings from glyph names
        # A full implementation would:
        # 1. Parse the Adobe Glyph List
        # 2. Map glyph names to Unicode codepoints
        # 3. Update the charstrings encoding
        #
        # For now, this is a no-op placeholder
        nil
      end

      # Decompose seac composite glyphs to base glyphs
      #
      # @param font [Type1Font] Source Type 1 font
      def decompose_seac_glyphs(font)
        return unless font.charstrings

        # Create SeacExpander to decompose composite glyphs
        expander = Type1::SeacExpander.new(font.charstrings, font.private_dict)

        # Get all composite glyphs
        composites = expander.composite_glyphs
        return if composites.empty?

        # Decompose each composite glyph
        composites.each do |glyph_name|
          decomposed = expander.decompose(glyph_name)
          next if decomposed.nil? || decomposed.empty?

          # Update the CharString with decomposed version
          # Access the charstrings hash directly and update
          charstrings_hash = font.charstrings.charstrings
          charstrings_hash[glyph_name] = decomposed

          # Mark as decomposed (no longer a seac composite)
          # The decomposed CharString no longer contains the seac operator
        end
      end

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
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Type 1 font data as PFB
      def convert_otf_to_type1(font, _options = {})
        # Extract CFF table
        cff_table = font.table("CFF ")
        raise Fontisan::Error, "CFF table not found" unless cff_table

        # Get CharStrings INDEX from CFF
        charstrings_index = cff_table.charstrings_index(0)
        raise Fontisan::Error, "CharStrings INDEX not found" unless charstrings_index

        # Get Private DICT for context
        private_dict = cff_table.private_dict(0)

        # Create CFF to Type 1 converter
        converter = Type1::CffToType1Converter.new(
          nominal_width: private_dict&.nominal_width || 0,
          default_width: private_dict&.default_width || 0
        )

        # Convert each CFF CharString to Type 1 format
        type1_charstrings = {}
        glyph_count = charstrings_index.count

        glyph_count.times do |glyph_index|
          # Get raw CFF CharString data
          cff_charstring = charstrings_index[glyph_index]
          next unless cff_charstring

          # Get glyph name
          glyph_name = font.glyph_name(glyph_index) || "glyph#{glyph_index}"

          # Convert CFF CharString to Type 1 format
          private_dict_hash = build_private_dict_hash(private_dict)
          type1_charstrings[glyph_name] = converter.convert(
            cff_charstring,
            private_dict: private_dict_hash
          )
        end

        # Build Type 1 font data
        build_type1_data(font, type1_charstrings, cff_table)
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

      # Build Type 1 Private dictionary hash from CFF Private dict
      #
      # @param private_dict [Tables::Cff::PrivateDict] CFF Private dict
      # @return [Hash] Private dictionary as hash for Type 1
      def build_private_dict_hash(private_dict)
        return {} unless private_dict

        {
          nominal_width: private_dict.nominal_width,
          default_width: private_dict.default_width,
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

      # Build Type 1 font data
      #
      # @param font [OpenTypeFont] Source OpenType font
      # @param charstrings [Hash] Type 1 CharStrings
      # @param cff_table [Tables::Cff] CFF table for metadata
      # @return [Hash] Type 1 font data with :pfb key
      def build_type1_data(_font, _charstrings, _cff_table)
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
      def build_head_table(font)
        data = (+"").b

        # Get font metadata from Type1Font
        font_bbox = font.font_dictionary&.font_bbox || [0, 0, 1000, 1000]
        version_str = font.version || "001.000"

        # Parse version (e.g., "001.000" => 1.0)
        version_parts = version_str.split(".")
        major = version_parts[0].to_i
        minor = version_parts[1]&.to_i || 0
        version = major + (minor / 1000.0)

        # Version (Fixed 16.16) - stored as int32
        integer_part = version.to_i
        fractional_part = ((version - integer_part) * 65_536).to_i
        version_raw = (integer_part << 16) | fractional_part
        data << [version_raw].pack("N")

        # Font Revision (Fixed 16.16) - default to 1.0
        font_revision_raw = 0x00010000
        data << [font_revision_raw].pack("N")

        # Checksum Adjustment (uint32) - will be calculated later
        data << [0].pack("N")

        # Magic Number (uint32)
        data << [0x5F0F3CF5].pack("N")

        # Flags (uint16) - bit 0 indicates y direction (0 = mixed)
        data << [0].pack("n")

        # Units Per Em (uint16) - Type 1 standard is 1000
        data << [1000].pack("n")

        # Created (LONGDATETIME) - use current time
        created_seconds = Time.now.to_i + 2_082_844_800
        data << [created_seconds].pack("Q>")

        # Modified (LONGDATETIME) - use current time
        modified_seconds = Time.now.to_i + 2_082_844_800
        data << [modified_seconds].pack("Q>")

        # Bounding box (int16 each)
        data << [font_bbox[0]].pack("s>") # x_min
        data << [font_bbox[1]].pack("s>") # y_min
        data << [font_bbox[2]].pack("s>") # x_max
        data << [font_bbox[3]].pack("s>") # y_max

        # Mac Style (uint16) - no style bits set
        data << [0].pack("n")

        # Lowest Rec PPEM (uint16) - readable size
        data << [8].pack("n")

        # Font Direction Hint (int16)
        # 2 = Left to right, mixed glyphs
        data << [2].pack("s>")

        # Index To Loc Format (int16)
        # 0 = short offsets (for CFF fonts we use this)
        data << [0].pack("s>")

        # Glyph Data Format (int16)
        data << [0].pack("s>")

        data
      end

      # Build hhea table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] hhea table binary data
      def build_hhea_table(font)
        data = (+"").b

        # Get font metrics from Type1Font
        font_bbox = font.font_dictionary&.font_bbox || [0, 0, 1000, 1000]
        blue_values = font.private_dict&.blue_values || []

        # Version (Fixed 16.16) - 0x00010000 (1.0)
        data << [0x00010000].pack("N")

        # Ascent (int16) - Distance from baseline to highest ascender
        # Use BlueValues[2] or [3] if available, otherwise font_bbox[3]
        if blue_values.length >= 4
          ascent = blue_values[3] # Top zone top
        elsif blue_values.length >= 3
          ascent = blue_values[2] # Top zone bottom
        else
          ascent = font_bbox[3] # y_max
        end
        data << [ascent].pack("s>")

        # Descent (int16) - Distance from baseline to lowest descender (negative)
        # Use BlueValues[0] or [1] if available, otherwise font_bbox[1]
        if blue_values.length >= 2
          descent = blue_values[0] # Bottom zone bottom (negative)
        elsif blue_values.length >= 1
          descent = blue_values[0]
        else
          descent = font_bbox[1] # y_min (should be negative)
        end
        data << [descent].pack("s>")

        # Line Gap (int16) - Additional space between lines
        # Use typical value of 0 for Type 1 fonts
        data << [0].pack("s>")

        # Advance Width Max (uint16)
        # Type 1 standard is typically 1000, use font_bbox width + padding
        advance_max = (font_bbox[2] - font_bbox[0]) + 100
        data << [advance_max].pack("n")

        # Min Left Side Bearing (int16)
        # Use font_bbox[0] (x_min) as reasonable default
        data << [font_bbox[0]].pack("s>")

        # Min Right Side Bearing (int16)
        # Estimate as 0 (will be updated if actual metrics available)
        data << [0].pack("s>")

        # x Max Extent (int16) - Max(lsb + xMax)
        # Use font_bbox[2] (x_max) as reasonable default
        data << [font_bbox[2]].pack("s>")

        # Caret Slope Rise (int16)
        # 1 for upright fonts (not italic)
        data << [1].pack("s>")

        # Caret Slope Run (int16)
        # 0 for upright fonts
        data << [0].pack("s>")

        # Caret Offset (int16)
        # Set to 0 for standard fonts
        data << [0].pack("s>")

        # Reserved (int64) - 8 bytes of zeros
        data << [0, 0].pack("Q>")

        # Metric Data Format (int16)
        # 0 for current format
        data << [0].pack("s>")

        # Number of HMetrics (uint16)
        # Number of glyphs with explicit metrics (typically all glyphs)
        num_glyphs = font.charstrings&.count || 1
        data << [[num_glyphs, 1].max].pack("n")

        data
      end

      # Build maxp table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] maxp table binary data
      def build_maxp_table(font)
        data = (+"").b

        # Get number of glyphs from Type1Font
        num_glyphs = font.charstrings&.count || 1

        # Version (Fixed 16.16)
        # For CFF fonts (OTF output), use version 0.5 (0x00005000)
        # For TrueType fonts (TTF output), would use version 1.0 (0x00010000)
        # Type 1 fonts convert to CFF-based OTF, so use version 0.5
        data << [0x00005000].pack("N")

        # Number of Glyphs (uint16)
        # Must be >= 1 (at minimum, .notdef must be present)
        data << [[num_glyphs, 1].max].pack("n")

        data
      end

      # Build name table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] name table binary data
      def build_name_table(font)
        # Get font metadata from Type1Font
        font_dict = font.font_dictionary
        font_info = font_dict&.font_info

        # Extract font names with fallbacks
        font_name = font.font_name || font_dict&.font_name || "Unnamed"
        family_name = if font_info&.respond_to?(:family_name)
                        font_info.family_name || font_dict&.family_name || font_name
                      else
                        font_dict&.family_name || font_name
                      end
        full_name = if font_info&.respond_to?(:full_name)
                      font_info.full_name || font_dict&.full_name || family_name
                    else
                      font_dict&.full_name || family_name
                    end
        version = if font_info&.respond_to?(:version)
                    font_info.version || font.version || "001.000"
                  else
                    font.version || "001.000"
                  end
        copyright = if font_info&.respond_to?(:copyright)
                       font_info.copyright || font_dict&.raw_data&.dig(:copyright) || ""
                     else
                       font_dict&.raw_data&.dig(:copyright) || ""
                     end
        postscript_name = font_name
        weight = if font_info&.respond_to?(:weight)
                   font_info.weight
                 else
                   "Regular"
                 end
        notice = if font_info&.respond_to?(:notice)
                   font_info.notice
                 else
                   ""
                 end

        # Build name records (Windows Unicode, English US)
        # Platform ID 3 (Windows), Encoding ID 1 (Unicode BMP), Language ID 0x0409 (US English)
        name_records = [
          # Copyright (name ID 0)
          { name_id: 0, string: copyright },
          # Family Name (name ID 1)
          { name_id: 1, string: family_name },
          # Subfamily Name (name ID 2) - derive from weight or default to Regular
          { name_id: 2, string: weight || "Regular" },
          # Unique ID (name ID 3) - format: version;copyright;postscript_name
          { name_id: 3, string: "#{version};#{copyright};#{postscript_name}" },
          # Full Name (name ID 4)
          { name_id: 4, string: full_name },
          # Version (name ID 5)
          { name_id: 5, string: version },
          # PostScript Name (name ID 6)
          { name_id: 6, string: postscript_name },
          # Trademark (name ID 7) - use notice if available
          { name_id: 7, string: notice || "" },
        ]

        # Filter out empty strings and build string storage
        name_records = name_records.select { |r| !r[:string].nil? && !r[:string].empty? }

        # Build string storage (UTF-16BE encoded for Windows platform)
        string_storage = (+"").b
        name_records.each do |record|
          encoded_string = record[:string].encode("UTF-16BE").force_encoding("ASCII-8BIT")
          record[:encoded] = encoded_string
          record[:offset] = string_storage.bytesize
          string_storage << encoded_string
        end

        # Build name table
        data = (+"").b

        # Format selector (uint16) - 0 for basic
        data << [0].pack("n")

        # Count (uint16) - number of name records
        data << [name_records.size].pack("n")

        # String offset (uint16) - offset to string storage from start of table
        # Header is 6 bytes, each name record is 12 bytes
        string_data_offset = 6 + (name_records.size * 12)
        data << [string_data_offset].pack("n")

        # Write name records
        platform_id = 3  # Windows
        encoding_id = 1  # Unicode BMP
        language_id = 0x0409  # US English

        name_records.each do |record|
          data << [platform_id].pack("n")           # platform ID
          data << [encoding_id].pack("n")           # encoding ID
          data << [language_id].pack("n")           # language ID
          data << [record[:name_id]].pack("n")      # name ID
          data << [record[:encoded].bytesize].pack("n")  # string length
          data << [record[:offset]].pack("n")       # string offset
        end

        # Write string storage
        data << string_storage

        data
      end

      # Build OS/2 table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] OS/2 table binary data
      def build_os2_table(font)
        data = (+"").b

        # Get font metadata from Type1Font
        font_bbox = font.font_dictionary&.font_bbox || [0, 0, 1000, 1000]
        blue_values = font.private_dict&.blue_values || []
        font_info = font.font_dictionary&.font_info || {}
        weight = font_info.weight || "Medium"

        # Determine weight class (100-900)
        # Order matters - more specific patterns must come first
        weight_class = case weight.to_s.downcase
                       when /thin/ then 100
                       when /extralight/ then 200
                       when /light/ then 300
                       when /regular|normal/ then 400
                       when /medium/ then 400
                       when /semibold|semib/ then 600
                       when /extrabold/ then 800
                       when /bold/ then 700
                       when /black|heavy/ then 900
                       else 400
                       end

        # Version (uint16) - Use version 4 for modern fonts
        data << [4].pack("n")

        # xAvgCharWidth (int16) - Average character width
        # Use font width estimate
        avg_width = ((font_bbox[2] - font_bbox[0]) * 0.5).to_i
        data << [avg_width].pack("s>")

        # usWeightClass (uint16)
        data << [weight_class].pack("n")

        # usWidthClass (uint16) - 1 = Ultra-condensed to 9 = Ultra-expanded
        # Default to 5 (Medium)
        data << [5].pack("n")

        # fsType (uint16) - Embedding permissions
        # 0 = Installable embedding, 8 = Restricted (use 0 as default)
        data << [0].pack("n")

        # ySubscriptXSize (int16)
        data << [650].pack("s>")

        # ySubscriptYSize (int16)
        data << [600].pack("s>")

        # ySubscriptXOffset (int16)
        data << [0].pack("s>")

        # ySubscriptYOffset (int16)
        data << [75].pack("s>")

        # ySuperscriptXSize (int16)
        data << [650].pack("s>")

        # ySuperscriptYSize (int16)
        data << [600].pack("s>")

        # ySuperscriptXOffset (int16)
        data << [0].pack("s>")

        # ySuperscriptYOffset (int16)
        data << [350].pack("s>")

        # yStrikeoutSize (int16)
        data << [50].pack("s>")

        # yStrikeoutPosition (int16)
        data << [300].pack("s>")

        # sFamilyClass (int16) - Family class and subclass
        # 0 = No classification
        data << [0].pack("s>")

        # PANOSE (10 bytes) - Use default Latin Text family
        # Family: 2 (Text and Display), Serif Style: 11 (Normal Sans)
        panose = [
          2,   # Family kind: Latin Text
          11,  # Serif style: Normal Sans
          5,   # Weight: Medium
          5,   # Proportion: Modern
          2,   # Contrast: Medium Low
          5,   # Stroke variation: Medium
          5,   # Arm style: Straight arms/serifs
          5,   # Letter form: Normal
          4,   # Midline: Standard
          3,   # X-height: Medium
        ]
        data << panose.pack("C*")

        # Unicode ranges (4 x uint32) - Basic Latin + Latin-1
        # Bits 0-31: Basic Latin, Latin-1, Latin Extended-A/B, etc.
        data << [0x00000001].pack("N")  # Basic Latin (0-7F)
        data << [0x00000000].pack("N")
        data << [0x00000000].pack("N")
        data << [0x00000000].pack("N")

        # achVendID (4 bytes) - Vendor ID
        data << "UKWN"  # Unknown

        # fsSelection (uint16) - Font selection flags
        # Bit 6 (0x40) = Regular weight if 400-500
        fs_selection = if weight_class >= 400 && weight_class <= 500
                         0x40  # REGULAR
                       elsif weight_class >= 700
                         0x20  # BOLD
                       else
                         0
                       end
        data << [fs_selection].pack("n")

        # usFirstCharIndex (uint16) - First Unicode character
        data << [32].pack("n")  # Space

        # usLastCharIndex (uint16) - Last Unicode character
        data << [0xFFFD].pack("n")  # Replacement character

        # sTypoAscender (int16) - Use BlueValues or font bbox
        if blue_values.length >= 4
          typo_ascender = blue_values[3]
        else
          typo_ascender = font_bbox[3]
        end
        data << [typo_ascender].pack("s>")

        # sTypoDescender (int16) - Use BlueValues or font bbox (negative)
        if blue_values.length >= 2
          typo_descender = blue_values[0]
        else
          typo_descender = font_bbox[1]
        end
        data << [typo_descender].pack("s>")

        # sTypoLineGap (int16)
        data << [0].pack("s>")

        # usWinAscent (uint16)
        data << [[font_bbox[3], 1000].max].pack("n")

        # usWinDescent (uint16)
        data << [[-font_bbox[1], 200].max].pack("n")

        # ulCodePageRange1 (uint32) - Latin 1
        data << [0x00000001].pack("N")

        # ulCodePageRange2 (uint32)
        data << [0x00000000].pack("N")

        # sxHeight (int16) - x-height, approximate as 500 for 1000 UPM
        data << [500].pack("s>")

        # sCapHeight (int16) - Cap height, approximate as 700 for 1000 UPM
        data << [700].pack("s>")

        # usDefaultChar (uint16)
        data << [0].pack("n")

        # usBreakChar (uint16) - Space
        data << [32].pack("n")

        # usMaxContext (uint16)
        data << [0].pack("n")

        data
      end

      # Build post table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] post table binary data
      def build_post_table(font)
        data = (+"").b

        # Get font metadata from Type1Font
        font_info = font.font_dictionary&.font_info || {}

        # Version (Fixed 16.16) - Use version 3.0 for CFF fonts (no glyph names)
        # Version 2.0 would include glyph names, but for OTF output version 3.0 is fine
        # since CFF table contains the glyph names
        data << [0x00030000].pack("N")  # Version 3.0

        # Italic Angle (Fixed 16.16)
        # Get from FontInfo if available, otherwise default to 0
        italic_angle = font_info.italic_angle || 0
        angle_raw = (italic_angle * 65_536).to_i
        data << [angle_raw].pack("N")

        # Underline Position (int16)
        underline_position = font_info.underline_position || -100
        data << [underline_position].pack("s>")

        # Underline Thickness (int16)
        underline_thickness = font_info.underline_thickness || 50
        data << [underline_thickness].pack("s>")

        # Fixed Pitch (uint32) - Boolean for monospace
        is_fixed_pitch = (font_info.is_fixed_pitch || false) ? 1 : 0
        data << [is_fixed_pitch].pack("N")

        # Min/Max Memory for Type 42 (uint32 each) - Not used for CFF, set to 0
        data << [0].pack("N")  # min_mem_type42
        data << [0].pack("N")  # max_mem_type42

        # Min/Max Memory for Type 1 (uint32 each) - Not used for CFF, set to 0
        data << [0].pack("N")  # min_mem_type1
        data << [0].pack("N")  # max_mem_type1

        data
      end

      # Build cmap table from Type 1 font
      #
      # @param font [Type1Font] Source Type 1 font
      # @return [String] cmap table binary data
      def build_cmap_table(font)
        require_relative "../type1/agl"

        data = (+"").b

        # Get encoding from Type1Font
        encoding = font.charstrings&.encoding || {}
        glyph_names = font.charstrings&.glyph_names || encoding.keys

        # Build Unicode mapping from glyph names using AGL
        unicode_to_glyph = {}
        glyph_index = 0

        glyph_names.each do |glyph_name|
          # Get Unicode code point from AGL
          unicode = Type1::AGL.unicode_for_glyph_name(glyph_name)

          # If no Unicode mapping, try to derive from encoding position
          if unicode.nil?
            # For standard encoding, try to map from position
            # This is a simplified approach - real implementation would be more robust
            unicode = glyph_index if glyph_index < 128
          end

          # Map Unicode to glyph index
          if unicode && unicode <= 0xFFFF
            unicode_to_glyph[unicode] ||= glyph_index
          end

          glyph_index += 1
        end

        # Ensure at least .notdef (glyph 0) maps to something
        unicode_to_glyph[0x0000] ||= 0

        # Build Format 4 subtable (Segment mapping to delta values)
        # This is the most common format for BMP Unicode fonts
        subtable_data = build_cmap_format_4(unicode_to_glyph)

        # Calculate offsets
        encoding_records_offset = 4  # After version (2) + num_tables (2)
        subtable_offset = encoding_records_offset + 8  # After one encoding record (8 bytes)

        # Build cmap table header
        # Version (uint16)
        data << [0].pack("n")

        # Number of encoding records (uint16)
        data << [1].pack("n")  # One encoding record

        # Encoding record: Platform ID (uint16), Encoding ID (uint16), Subtable offset (uint32)
        # Platform 3 (Windows), Encoding 1 (Unicode BMP)
        data << [3].pack("n")           # Platform ID: Windows
        data << [1].pack("n")           # Encoding ID: Unicode BMP
        data << [subtable_offset].pack("N")  # Subtable offset

        # Append subtable data
        data << subtable_data

        data
      end

      # Build cmap format 4 subtable
      #
      # @param unicode_to_glyph [Hash<Integer, Integer>] Unicode to glyph index mapping
      # @return [String] Format 4 subtable binary data
      def build_cmap_format_4(unicode_to_glyph)
        data = (+"").b

        # Get sorted Unicode values
        unicode_values = unicode_to_glyph.keys.sort
        return data if unicode_values.empty?

        # For simplicity, create segments for continuous ranges
        # A more sophisticated implementation would optimize this
        segments = []
        current_segment = nil

        unicode_values.each do |unicode|
          glyph_id = unicode_to_glyph[unicode]

          if current_segment.nil?
            current_segment = {
              start: unicode,
              end: unicode,
              start_glyph: glyph_id,
              glyphs: [glyph_id],
            }
          elsif unicode == current_segment[:end] + 1 && glyph_id == current_segment[:glyphs].last + 1
            # Continue current segment (sequential)
            current_segment[:end] = unicode
            current_segment[:glyphs] << glyph_id
          else
            # Start new segment
            segments << current_segment
            current_segment = {
              start: unicode,
              end: unicode,
              start_glyph: glyph_id,
              glyphs: [glyph_id],
            }
          end
        end

        segments << current_segment if current_segment

        # Add end segment marker (0xFFFF)
        segments << { start: 0xFFFF, end: 0xFFFF, start_glyph: 0, glyphs: [0] }

        # Calculate segment count and related values
        seg_count = segments.length
        seg_count_x2 = seg_count * 2
        search_range = 2 ** (Math.log2(seg_count).to_i) * 2
        entry_selector = Math.log2(search_range / 2).to_i
        range_shift = (seg_count - search_range / 2) * 2

        # Build format 4 subtable header (14 bytes)
        data << [4].pack("n")                    # Format
        data << [calculate_cmap4_length(segments)].pack("n")  # Length (placeholder)
        data << [0].pack("n")                    # Language (0 = independent)
        data << [seg_count_x2].pack("n")         # segCountX2
        data << [search_range].pack("n")         # searchRange
        data << [entry_selector].pack("n")       # entrySelector
        data << [range_shift].pack("n")          # rangeShift

        # Build segment arrays
        end_codes = []
        start_codes = []
        id_deltas = []
        id_range_offsets = []
        glyph_id_array = []

        segments.each do |seg|
          end_codes << seg[:end]
          start_codes << seg[:start]

          # For sequential glyphs, use delta
          if seg[:start] == 0xFFFF
            # End segment marker
            id_deltas << 1
            id_range_offsets << 0
          elsif seg[:end] - seg[:start] == seg[:glyphs].length - 1
            # Sequential: use delta
            id_deltas << (seg[:start_glyph] - seg[:start])
            id_range_offsets << 0
          else
            # Non-sequential: use glyph ID array
            id_deltas << 0
            id_range_offsets << (glyph_id_array.length * 2 + 2)
            glyph_id_array.concat(seg[:glyphs])
          end
        end

        # Write arrays (padded to even length)
        end_codes.each { |code| data << [code].pack("n") }
        data << [0].pack("n")  # Reserved padding
        start_codes.each { |code| data << [code].pack("n") }
        id_deltas.each { |delta| data << [delta].pack("s>") }  # Signed
        id_range_offsets.each { |offset| data << [offset].pack("n") }
        glyph_id_array.each { |gid| data << [gid].pack("n") }

        # Update length in header
        length = data.bytesize
        data[2..3] = [length].pack("n")

        data
      end

      # Calculate length for format 4 subtable
      #
      # @param segments [Array<Hash>] Segment definitions
      # @return [Integer] Estimated length
      def calculate_cmap4_length(segments)
        # Header: 14 bytes
        # Arrays: seg_count * 2 bytes each
        # Glyph ID array: variable
        seg_count = segments.length

        # Rough estimate (actual calculation done during construction)
        14 + (seg_count * 8) + (seg_count * 2) + 100  # 100 for glyph ID array estimate
      end
    end
  end
end
