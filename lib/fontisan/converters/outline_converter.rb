# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../outline_extractor"
require_relative "../models/outline"
require_relative "../tables/cff/charstring_builder"
require_relative "../tables/cff/index_builder"
require_relative "../tables/cff/dict_builder"
require_relative "../tables/glyf/glyph_builder"
require_relative "../tables/glyf/compound_glyph_resolver"

module Fontisan
  module Converters
    # Strategy for converting between TTF and OTF outline formats
    #
    # [`OutlineConverter`](lib/fontisan/converters/outline_converter.rb)
    # handles conversion between TrueType (glyf/loca) and CFF outline formats.
    # This involves:
    # - Extracting glyph outlines from source format
    # - Converting to universal [`Outline`](lib/fontisan/models/outline.rb) model
    # - Building target format tables using specialized builders
    # - Updating related tables (maxp, head)
    # - Preserving all other font tables
    #
    # **Conversion Details:**
    #
    # TTF → OTF:
    # - Extract glyphs from glyf/loca tables
    # - Convert TrueType quadratic curves to universal format
    # - Build complete CFF table with CharStrings INDEX
    # - Remove glyf/loca tables
    # - Update maxp to version 0.5 (CFF format)
    # - Update head table (clear indexToLocFormat)
    #
    # OTF → TTF:
    # - Extract CharStrings from CFF table
    # - Convert CFF cubic curves to universal format
    # - Build glyf and loca tables
    # - Remove CFF table
    # - Update maxp to version 1.0 (TrueType format)
    # - Update head table (set indexToLocFormat)
    #
    # @example Converting TTF to OTF
    #   converter = Fontisan::Converters::OutlineConverter.new
    #   otf_font = converter.convert(ttf_font, target_format: :otf)
    #
    # @example Converting OTF to TTF
    #   converter = Fontisan::Converters::OutlineConverter.new
    #   ttf_font = converter.convert(otf_font, target_format: :ttf)
    class OutlineConverter
      include ConversionStrategy

      # @return [TrueTypeFont, OpenTypeFont] Source font
      attr_reader :font

      # Initialize converter
      def initialize
        @font = nil
      end

      # Convert font between TTF and OTF formats
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param options [Hash] Conversion options
      # @option options [Symbol] :target_format Target format (:ttf or :otf)
      # @return [Hash<String, String>] Map of table tags to binary data
      def convert(font, options = {})
        @font = font
        @options = options
        target_format = options[:target_format] ||
          detect_target_format(font)
        validate(font, target_format)

        source_format = detect_format(font)

        case [source_format, target_format]
        when %i[ttf otf]
          convert_ttf_to_otf(font, options)
        when %i[otf ttf]
          convert_otf_to_ttf(font)
        else
          raise Fontisan::Error,
                "Unsupported conversion: #{source_format} → #{target_format}"
        end
      end

      # Convert TrueType font to OpenType/CFF
      #
      # @param font [TrueTypeFont] Source font
      # @param options [Hash] Conversion options (currently unused)
      # @return [Hash<String, String>] Target tables
      def convert_ttf_to_otf(font, options = {})
        # Extract all glyphs from glyf table
        outlines = extract_ttf_outlines(font)

        # Build CFF table from outlines
        cff_data = build_cff_table(outlines, font)

        # Copy all tables except glyf/loca
        tables = copy_tables(font, %w[glyf loca])

        # Add CFF table
        tables["CFF "] = cff_data

        # Update maxp table for CFF
        tables["maxp"] = update_maxp_for_cff(font, outlines.length)

        # Update head table for CFF
        tables["head"] = update_head_for_cff(font)

        tables
      end

      # Convert OpenType/CFF font to TrueType
      #
      # @param font [OpenTypeFont] Source font
      # @return [Hash<String, String>] Target tables
      def convert_otf_to_ttf(font)
        # Extract all glyphs from CFF table
        outlines = extract_cff_outlines(font)

        # Build glyf and loca tables
        glyf_data, loca_data, loca_format = build_glyf_loca_tables(outlines)

        # Copy all tables except CFF
        tables = copy_tables(font, ["CFF ", "CFF2"])

        # Add glyf and loca tables
        tables["glyf"] = glyf_data
        tables["loca"] = loca_data

        # Update maxp table for TrueType
        tables["maxp"] = update_maxp_for_truetype(font, outlines, loca_format)

        # Update head table for TrueType
        tables["head"] = update_head_for_truetype(font, loca_format)

        tables
      end

      # Convert TrueType font to OpenType/CFF
      #
      # @return [Hash<String, String>] Target tables
      def ttf_to_otf
        raise Fontisan::Error, "No font loaded" unless @font

        convert_ttf_to_otf(@font)
      end

      # Convert OpenType/CFF font to TrueType
      #
      # @return [Hash<String, String>] Target tables
      def otf_to_ttf
        raise Fontisan::Error, "No font loaded" unless @font

        convert_otf_to_ttf(@font)
      end

      # Get supported conversions
      #
      # @return [Array<Array<Symbol>>] Supported conversion pairs
      def supported_conversions
        [
          %i[ttf otf],
          %i[otf ttf],
        ]
      end

      # Validate font for conversion
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param target_format [Symbol] Target format
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If font is invalid
      # @raise [Error] If conversion is not supported
      def validate(font, target_format)
        raise ArgumentError, "Font cannot be nil" if font.nil?

        unless font.respond_to?(:tables)
          raise ArgumentError, "Font must respond to :tables"
        end

        unless font.respond_to?(:table)
          raise ArgumentError, "Font must respond to :table"
        end

        source_format = detect_format(font)
        unless supports?(source_format, target_format)
          raise Fontisan::Error,
                "Conversion #{source_format} → #{target_format} not supported"
        end

        # Check that source font has required tables
        validate_source_tables(font, source_format)

        true
      end

      # Extract outlines from TrueType font
      #
      # @param font [TrueTypeFont] Source font
      # @return [Array<Outline>] Array of outline objects
      def extract_ttf_outlines(font)
        # Get required tables
        head = font.table("head")
        maxp = font.table("maxp")
        loca = font.table("loca")
        glyf = font.table("glyf")

        # Parse loca with context
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)

        # Create resolver for compound glyphs
        resolver = Tables::CompoundGlyphResolver.new(glyf, loca, head)

        # Extract all glyphs
        outlines = []
        maxp.num_glyphs.times do |glyph_id|
          glyph = glyf.glyph_for(glyph_id, loca, head)

          outlines << if glyph.nil? || glyph.empty?
                        # Empty glyph - create empty outline
                        Models::Outline.new(
                          glyph_id: glyph_id,
                          commands: [],
                          bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
                        )
                      elsif glyph.simple?
                        # Convert simple glyph to outline
                        Models::Outline.from_truetype(glyph, glyph_id)
                      else
                        # Compound glyph - resolve to simple outline
                        resolver.resolve(glyph)
                      end
        end

        outlines
      end

      # Extract outlines from CFF font
      #
      # @param font [OpenTypeFont] Source font
      # @return [Array<Outline>] Array of outline objects
      def extract_cff_outlines(font)
        # Get CFF table
        cff = font.table("CFF ")
        raise Fontisan::Error, "CFF table not found" unless cff

        # Get number of glyphs
        num_glyphs = cff.glyph_count

        # Extract all glyphs
        outlines = []
        num_glyphs.times do |glyph_id|
          charstring = cff.charstring_for_glyph(glyph_id)

          outlines << if charstring.nil? || charstring.path.empty?
                        # Empty glyph
                        Models::Outline.new(
                          glyph_id: glyph_id,
                          commands: [],
                          bbox: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 },
                        )
                      else
                        # Convert CharString to outline
                        Models::Outline.from_cff(charstring, glyph_id)
                      end
        end

        outlines
      end

      # Build CFF table from outlines
      #
      # @param outlines [Array<Outline>] Glyph outlines
      # @param font [TrueTypeFont] Source font (for metadata)
      # @return [String] CFF table binary data
      def build_cff_table(outlines, font)
        # Build CharStrings INDEX from outlines
        begin
          charstrings = outlines.map do |outline|
            builder = Tables::Cff::CharStringBuilder.new
            if outline.empty?
              builder.build_empty
            else
              builder.build(outline)
            end
          end
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build CharStrings: #{e.message}"
        end

        begin
          charstrings_index_data = Tables::Cff::IndexBuilder.build(charstrings)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build CharStrings INDEX: #{e.message}"
        end

        # Build empty Local Subrs INDEX (no optimization)
        begin
          local_subrs_index_data = Tables::Cff::IndexBuilder.build([])
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build Local Subrs INDEX: #{e.message}"
        end

        # Build Private DICT
        begin
          private_dict_hash = {
            default_width_x: 1000,
            nominal_width_x: 0,
          }

          private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build Private DICT: #{e.message}"
        end

        # Build font metadata
        begin
          font_name = extract_font_name(font)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to extract font name: #{e.message}"
        end

        # CFF structure: Header + Name INDEX + Top DICT INDEX + String INDEX + Global Subr INDEX + CharStrings + Private DICT + Local Subrs
        begin
          header_size = 4
          name_index_data = Tables::Cff::IndexBuilder.build([font_name])
          string_index_data = Tables::Cff::IndexBuilder.build([]) # Empty strings
          global_subr_index_data = Tables::Cff::IndexBuilder.build([]) # Empty global subrs
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build CFF indexes: #{e.message}"
        end

        # Calculate offset to CharStrings from start of CFF table
        begin
          # First pass: build Top DICT with approximate CharStrings offset
          top_dict_index_start = header_size + name_index_data.bytesize
          string_index_start = top_dict_index_start + 100 # Approximate
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize

          top_dict_hash = {
            charset: 0, # ISOAdobe
            encoding: 0, # Standard encoding
            charstrings: charstrings_offset,
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

          # Second pass: recalculate with actual Top DICT size
          string_index_start = top_dict_index_start + top_dict_index_data.bytesize
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize

          # Calculate Private DICT location (after CharStrings)
          private_dict_offset = charstrings_offset + charstrings_index_data.bytesize
          private_dict_size = private_dict_data.bytesize

          # Update Top DICT with CharStrings offset and Private DICT info
          top_dict_hash = {
            charset: 0,
            encoding: 0,
            charstrings: charstrings_offset,
            private: [private_dict_size, private_dict_offset],
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

          # Final recalculation to ensure accuracy
          string_index_start = top_dict_index_start + top_dict_index_data.bytesize
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize
          private_dict_offset = charstrings_offset + charstrings_index_data.bytesize

          # Rebuild Top DICT with final offsets
          top_dict_hash = {
            charset: 0,
            encoding: 0,
            charstrings: charstrings_offset,
            private: [private_dict_size, private_dict_offset],
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])
        rescue StandardError => e
          raise Fontisan::Error, "Failed to calculate CFF table offsets: #{e.message}"
        end

        # Build CFF Header
        begin
          header = [
            1,    # major version
            0,    # minor version
            4,    # header size
            4,    # offSize (will be in INDEX)
          ].pack("C4")
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build CFF header: #{e.message}"
        end

        # Assemble complete CFF table
        begin
          header +
            name_index_data +
            top_dict_index_data +
            string_index_data +
            global_subr_index_data +
            charstrings_index_data +
            private_dict_data +
            local_subrs_index_data
        rescue StandardError => e
          raise Fontisan::Error, "Failed to assemble CFF table: #{e.message}"
        end
      end

      # Build glyf and loca tables from outlines
      #
      # @param outlines [Array<Outline>] Glyph outlines
      # @return [Array<String, String, Integer>] [glyf_data, loca_data, loca_format]
      def build_glyf_loca_tables(outlines)
        glyf_data = "".b
        offsets = []

        # Build each glyph
        outlines.each do |outline|
          offsets << glyf_data.bytesize

          if outline.empty?
            # Empty glyph - no data
            next
          end

          # Convert outline to TrueType contours
          contours = outline.to_truetype_contours

          # Build glyph data
          builder = Tables::Glyf::GlyphBuilder.new(
            contours: contours,
            x_min: outline.bbox[:x_min],
            y_min: outline.bbox[:y_min],
            x_max: outline.bbox[:x_max],
            y_max: outline.bbox[:y_max],
          )

          glyph_data = builder.build
          glyf_data << glyph_data

          # Add padding to 4-byte boundary
          padding = (4 - (glyf_data.bytesize % 4)) % 4
          glyf_data << ("\x00" * padding) if padding.positive?
        end

        # Add final offset
        offsets << glyf_data.bytesize

        # Build loca table
        # Determine format based on max offset
        max_offset = offsets.max
        if max_offset <= 0x1FFFE
          # Short format (offsets / 2)
          loca_format = 0
          loca_data = offsets.map { |off| off / 2 }.pack("n*")
        else
          # Long format
          loca_format = 1
          loca_data = offsets.pack("N*")
        end

        [glyf_data, loca_data, loca_format]
      end

      # Copy non-outline tables from source to target
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param exclude_tags [Array<String>] Tags to exclude
      # @return [Hash<String, String>] Copied tables
      def copy_tables(font, exclude_tags = [])
        tables = {}

        font.table_data.each do |tag, data|
          next if exclude_tags.include?(tag)

          tables[tag] = data if data
        end

        tables
      end

      # Update maxp table for CFF format
      #
      # @param font [TrueTypeFont] Source font
      # @param num_glyphs [Integer] Number of glyphs
      # @return [String] Updated maxp table binary data
      def update_maxp_for_cff(_font, num_glyphs)
        # CFF uses maxp version 0.5 (0x00005000)
        # Structure: version (4 bytes) + numGlyphs (2 bytes)
        [Tables::Maxp::VERSION_0_5, num_glyphs].pack("Nn")
      end

      # Update maxp table for TrueType format
      #
      # @param font [OpenTypeFont] Source font
      # @param outlines [Array<Outline>] Glyph outlines
      # @param loca_format [Integer] Loca format (0 or 1)
      # @return [String] Updated maxp table binary data
      def update_maxp_for_truetype(font, outlines, _loca_format)
        # Get source maxp
        font.table("maxp")
        num_glyphs = outlines.length

        # Calculate statistics from outlines
        max_points = 0
        max_contours = 0

        outlines.each do |outline|
          next if outline.empty?

          contours = outline.to_truetype_contours
          max_contours = [max_contours, contours.length].max

          contours.each do |contour|
            max_points = [max_points, contour.length].max
          end
        end

        # Build maxp v1.0 table
        # We'll use conservative defaults for instruction-related fields
        [
          Tables::Maxp::VERSION_1_0, # version
          num_glyphs,                  # numGlyphs
          max_points,                  # maxPoints
          max_contours,                # maxContours
          0,                           # maxCompositePoints
          0,                           # maxCompositeContours
          2,                           # maxZones
          0,                           # maxTwilightPoints
          0,                           # maxStorage
          0,                           # maxFunctionDefs
          0,                           # maxInstructionDefs
          0,                           # maxStackElements
          0,                           # maxSizeOfInstructions
          0,                           # maxComponentElements
          0,                           # maxComponentDepth
        ].pack("Nnnnnnnnnnnnnnnn")
      end

      # Update head table for CFF format
      #
      # @param font [TrueTypeFont] Source font
      # @return [String] Updated head table binary data
      def update_head_for_cff(font)
        font.table("head")
        head_data = font.table_data["head"].dup

        # For CFF fonts, indexToLocFormat is not relevant
        # but we'll set it to 0 for consistency
        # indexToLocFormat is at offset 50 (2 bytes)
        head_data[50, 2] = [0].pack("n")

        head_data
      end

      # Update head table for TrueType format
      #
      # @param font [OpenTypeFont] Source font
      # @param loca_format [Integer] Loca format (0=short, 1=long)
      # @return [String] Updated head table binary data
      def update_head_for_truetype(font, loca_format)
        font.table("head")
        head_data = font.table_data["head"].dup

        # Set indexToLocFormat at offset 50 (2 bytes)
        head_data[50, 2] = [loca_format].pack("n")

        head_data
      end

      # Extract font name from name table
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font
      # @return [String] Font name
      def extract_font_name(font)
        name_table = font.table("name")
        if name_table
          font_name = name_table.english_name(Tables::Name::FAMILY)
          return font_name.dup.force_encoding("ASCII-8BIT") if font_name
        end

        "UnnamedFont"
      end

      # Detect font format from tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Symbol] Format (:ttf or :otf)
      # @raise [Error] If format cannot be detected
      def detect_format(font)
        # Check for CFF/CFF2 tables (OpenType/CFF)
        if font.has_table?("CFF ") || font.has_table?("CFF2")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Fontisan::Error,
                "Cannot detect font format: missing both CFF and glyf tables"
        end
      end

      # Detect target format as opposite of source
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @return [Symbol] Target format
      def detect_target_format(font)
        source = detect_format(font)
        source == :ttf ? :otf : :ttf
      end

      # Validate source font has required tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param format [Symbol] Font format
      # @raise [Error] If required tables are missing
      def validate_source_tables(font, format)
        case format
        when :ttf
          unless font.has_table?("glyf") && font.has_table?("loca") &&
              font.table("glyf") && font.table("loca")
            raise Fontisan::MissingTableError,
                  "TrueType font missing required glyf or loca table"
          end
        when :otf
          unless (font.has_table?("CFF ") && font.table("CFF ")) ||
              (font.has_table?("CFF2") && font.table("CFF2"))
            raise Fontisan::MissingTableError,
                  "OpenType font missing required CFF table"
          end
        end

        # Common required tables
        %w[head hhea maxp].each do |tag|
          unless font.table(tag)
            raise Fontisan::MissingTableError,
                  "Font missing required #{tag} table"
          end
        end
      end
    end
  end
end
