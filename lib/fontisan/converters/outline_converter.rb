# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../outline_extractor"
require_relative "../models/outline"
require_relative "../tables/cff/charstring_builder"
require_relative "../tables/cff/index_builder"
require_relative "../tables/cff/dict_builder"
require_relative "../tables/glyf/glyph_builder"
require_relative "../tables/glyf/compound_glyph_resolver"
require_relative "../optimizers/subroutine_generator"

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
      # @option options [Boolean] :optimize_subroutines Enable subroutine optimization (TTF→OTF only)
      # @option options [Boolean] :stack_aware Enable stack-aware pattern detection (default: false)
      # @option options [Integer] :min_pattern_length Minimum pattern length for subroutines (default: 10)
      # @option options [Integer] :max_subroutines Maximum number of subroutines (default: 65_535)
      # @option options [Boolean] :optimize_ordering Optimize subroutine ordering (default: true)
      # @option options [Boolean] :verbose Show detailed optimization statistics
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
      # @param options [Hash] Conversion options
      # @return [Hash<String, String>] Target tables
      def convert_ttf_to_otf(font, options = {})
        # Extract all glyphs from glyf table
        outlines = extract_ttf_outlines(font)

        # Build CharStrings from outlines first
        charstrings = outlines.map do |outline|
          builder = Tables::Cff::CharStringBuilder.new
          if outline.empty?
            builder.build_empty
          else
            builder.build(outline)
          end
        end

        # Optimize CharStrings if requested
        optimization_result = nil
        if options[:optimize_subroutines]
          begin
            optimization_result = optimize_charstrings_directly(
              charstrings,
              options,
            )
          rescue Fontisan::Error, StandardError => e
            # Optimization failed - log and continue without optimization
            if options[:verbose]
              puts "Note: Subroutine optimization failed (#{e.message})"
              puts "Continuing with unoptimized conversion..."
            end
            optimization_result = nil
          end
        end

        # Build CFF table with optimized CharStrings (if optimization succeeded)
        cff_data = build_cff_table(outlines, font, optimization_result)

        # Copy all tables except glyf/loca
        tables = copy_tables(font, %w[glyf loca])

        # Add CFF table
        tables["CFF "] = cff_data

        # Store optimization result for access by caller
        if optimization_result
          tables.instance_variable_set(:@subroutine_optimization, optimization_result)
        end

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
      # @param optimization_result [Hash, nil] Optional subroutine optimization result
      # @return [String] CFF table binary data
      def build_cff_table(outlines, font, optimization_result = nil)
        # Build CharStrings INDEX
        # Use rewritten CharStrings if optimization was performed
        begin
          charstrings = if optimization_result && optimization_result[:charstrings]
                          # Use optimized CharStrings with subroutine calls
                          optimization_result[:charstrings].values
                        else
                          # Build CharStrings from outlines normally
                          outlines.map do |outline|
                            builder = Tables::Cff::CharStringBuilder.new
                            if outline.empty?
                              builder.build_empty
                            else
                              builder.build(outline)
                            end
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

        # Build Local Subrs INDEX if optimization was performed
        begin
          local_subrs_index_data = if optimization_result && optimization_result[:local_subrs]
                                     Tables::Cff::IndexBuilder.build(optimization_result[:local_subrs])
                                   else
                                     Tables::Cff::IndexBuilder.build([]) # Empty
                                   end
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build Local Subrs INDEX: #{e.message}"
        end

        # Build Private DICT
        # Private DICT needs to reference Local Subrs if present
        begin
          private_dict_hash = {
            default_width_x: 1000,
            nominal_width_x: 0,
          }

          # Add Subrs pointer if we have subroutines
          if optimization_result && optimization_result[:local_subrs] && !optimization_result[:local_subrs].empty?
            # Subrs offset is relative to Private DICT start
            # It will be at the end of the Private DICT data
            # We'll calculate this after building the dict
            private_dict_hash[:subrs] = 0 # Placeholder, will update
          end

          private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build Private DICT: #{e.message}"
        end

        # If we have subroutines, append Local Subrs INDEX after Private DICT
        # and update Subrs offset in the dict
        if optimization_result && optimization_result[:local_subrs] && !optimization_result[:local_subrs].empty?
          begin
            # Subrs offset is the size of the Private DICT data
            subrs_offset = private_dict_data.bytesize

            # Rebuild Private DICT with correct Subrs offset
            private_dict_hash[:subrs] = subrs_offset
            private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
          rescue StandardError => e
            raise Fontisan::Error, "Failed to update Private DICT with Subrs offset: #{e.message}"
          end
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
        # We need to account for: Header + Name INDEX + Top DICT INDEX + String INDEX + Global Subr INDEX
        # Top DICT INDEX size is not yet known, so we'll calculate it iteratively

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

          # Private DICT size is just the dict data, NOT including Local Subrs
          # Local Subrs INDEX is separate and comes after the Private DICT
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

      # Optimize CFF table with subroutines
      #
      # @param tables [Hash] Current table data (containing CFF table)
      # @param font [TrueTypeFont] Source font (for creating temporary font object)
      # @param options [Hash] Optimization options
      # @return [Hash] Optimization result with metrics
      def optimize_cff_subroutines(tables, font, options)
        # Create a temporary font object with the new CFF table
        # so SubroutineGenerator can read CharStrings
        temp_font = create_temp_font(font, tables)

        # Create generator with options
        generator = Fontisan::Optimizers::SubroutineGenerator.new(
          min_pattern_length: options[:min_pattern_length] || 10,
          max_subroutines: options[:max_subroutines] || 65_535,
          optimize_ordering: options[:optimize_ordering] != false,
        )

        # Generate subroutines
        result = generator.generate(temp_font)

        # Log results if verbose
        log_optimization_results(result) if options[:verbose]

        # Note: Actual CFF table updating with subroutines requires CFF writing support
        # For now, we return the result which includes all generated data
        # The result can be used later when CFF serialization is implemented

        result
      rescue StandardError => e
        # Optimization failed - this is expected for TTF->OTF conversion
        # until full CFF serialization is implemented
        # Return a stub result indicating no optimization occurred
        puts "Note: Subroutine optimization skipped (#{e.message})" if options[:verbose]

        {
          pattern_count: 0,
          selected_count: 0,
          local_subrs: [],
          bias: 0,
          savings: 0,
          processing_time: 0.0,
          subroutines: [],
        }
      end

      # Optimize CharStrings directly without parsing CFF table
      #
      # This method works with raw CharString bytes and avoids the circular
      # dependency of parsing a CFF table we just created.
      #
      # @param charstrings [Array<String>] Raw CharString bytes
      # @param options [Hash] Optimization options
      # @return [Hash, nil] Optimization result with metrics, or nil if failed
      def optimize_charstrings_directly(charstrings, options)
        # Create a hash mapping glyph_id => charstring_bytes for the analyzer
        charstrings_hash = {}
        charstrings.each_with_index do |cs, index|
          charstrings_hash[index] = cs
        end

        # Create generator with options
        Fontisan::Optimizers::SubroutineGenerator.new(
          min_pattern_length: options[:min_pattern_length] || 10,
          max_subroutines: options[:max_subroutines] || 65_535,
          optimize_ordering: options[:optimize_ordering] != false,
          stack_aware: options[:stack_aware],
        )

        # Manually run the optimization pipeline
        start_time = Time.now

        # 1. Analyze patterns
        if options[:verbose]
          puts "Analyzing CharString patterns (#{charstrings.length} glyphs)..."
        end

        begin
          analyzer = Fontisan::Optimizers::PatternAnalyzer.new(
            min_length: options[:min_pattern_length] || 10,
            stack_aware: options[:stack_aware],
          )
          patterns = analyzer.analyze(charstrings_hash)

          if options[:verbose]
            puts "  Found #{patterns.length} potential patterns"
          end
        rescue StandardError => e
          raise Fontisan::Error, "Pattern analysis failed: #{e.message}"
        end

        # 2. Optimize selection
        if options[:verbose]
          puts "Selecting optimal patterns..."
        end

        begin
          optimizer = Fontisan::Optimizers::SubroutineOptimizer.new(
            patterns,
            max_subrs: options[:max_subroutines] || 65_535,
          )
          selected_patterns = optimizer.optimize_selection

          if options[:verbose]
            puts "  Selected #{selected_patterns.length} patterns for subroutinization"
          end
        rescue StandardError => e
          raise Fontisan::Error, "Pattern selection failed: #{e.message}"
        end

        # 3. Optimize ordering (if enabled)
        if options[:optimize_ordering] != false
          if options[:verbose]
            puts "Optimizing subroutine ordering..."
          end

          begin
            selected_patterns = optimizer.optimize_ordering(selected_patterns)
          rescue StandardError => e
            raise Fontisan::Error, "Pattern ordering failed: #{e.message}"
          end
        end

        # 4. Build subroutines
        if options[:verbose]
          puts "Building subroutines..."
        end

        begin
          builder = Fontisan::Optimizers::SubroutineBuilder.new(
            selected_patterns,
            type: :local,
          )
          subroutines = builder.build

          if options[:verbose]
            puts "  Generated #{subroutines.length} subroutines"
          end
        rescue StandardError => e
          raise Fontisan::Error, "Subroutine building failed: #{e.message}"
        end

        # 5. Build subroutine map
        subroutine_map = {}
        selected_patterns.each_with_index do |pattern, index|
          subroutine_map[pattern.bytes] = index
        end

        # 6. Rewrite CharStrings
        if options[:verbose]
          puts "Rewriting CharStrings with subroutine calls..."
        end

        begin
          rewriter = Fontisan::Optimizers::CharstringRewriter.new(
            subroutine_map,
            builder,
          )

          # OPTIMIZATION: Pre-build reverse index (glyph_id => patterns)
          # This avoids O(n*m) complexity when rewriting CharStrings
          glyph_to_patterns = Hash.new { |h, k| h[k] = [] }
          selected_patterns.each do |pattern|
            pattern.glyphs.each do |glyph_id|
              glyph_to_patterns[glyph_id] << pattern
            end
          end

          rewritten_charstrings = {}
          charstrings_hash.each do |glyph_id, charstring|
            glyph_patterns = glyph_to_patterns[glyph_id]

            rewritten_charstrings[glyph_id] = if glyph_patterns.empty?
                                                charstring
                                              else
                                                rewriter.rewrite(charstring, glyph_patterns)
                                              end
          end

          if options[:verbose]
            puts "  Rewrote #{charstrings.length} CharStrings"
          end
        rescue StandardError => e
          raise Fontisan::Error, "CharString rewriting failed: #{e.message}"
        end

        processing_time = Time.now - start_time

        result = {
          local_subrs: subroutines,
          charstrings: rewritten_charstrings,
          bias: builder.bias,
          savings: selected_patterns.sum(&:savings),
          pattern_count: patterns.length,
          selected_count: selected_patterns.length,
          processing_time: processing_time,
          subroutines: selected_patterns.map do |pattern|
            {
              commands: pattern.bytes,
              usage_count: pattern.frequency,
              savings: pattern.savings,
            }
          end,
        }

        # Log results if verbose
        log_optimization_results(result) if options[:verbose]

        result
      rescue Fontisan::Error
        # Re-raise our own errors
        raise
      rescue StandardError => e
        # Wrap unexpected errors with context
        raise Fontisan::Error, "Subroutine optimization failed unexpectedly: #{e.message}"
      end

      # Create temporary font object with updated tables for optimization
      #
      # @param source_font [TrueTypeFont] Original source font
      # @param tables [Hash] New table data
      # @return [OpenTypeFont] Temporary font object
      def create_temp_font(_source_font, tables)
        # Create a minimal font-like object that can provide the CFF table
        # This allows SubroutineGenerator to extract CharStrings
        temp_font = Object.new

        # Define methods needed by SubroutineGenerator
        temp_font.define_singleton_method(:table) do |tag|
          return nil unless tables[tag]

          # Parse CFF table if requested
          if tag == "CFF "
            cff = Fontisan::Tables::Cff.new
            cff.parse!(tables[tag])
            cff
          end
        end

        temp_font.define_singleton_method(:has_table?) do |tag|
          tables.key?(tag)
        end

        temp_font
      end

      # Log optimization results to console
      #
      # @param result [Hash] Optimization result from SubroutineGenerator
      def log_optimization_results(result)
        puts "\nSubroutine Optimization Results:"
        puts "  Patterns found: #{result[:pattern_count]}"
        puts "  Patterns selected: #{result[:selected_count]}"
        puts "  Subroutines generated: #{result[:local_subrs].length}"
        puts "  Estimated bytes saved: #{result[:savings]}"
        puts "  CFF bias: #{result[:bias]}"

        if result[:selected_count].zero?
          puts "  Note: No beneficial patterns found for optimization"
        end
      end
    end
  end
end
