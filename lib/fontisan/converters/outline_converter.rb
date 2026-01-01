# frozen_string_literal: true

require_relative "conversion_strategy"
require_relative "../outline_extractor"
require_relative "../models/outline"
require_relative "../tables/cff/charstring_builder"
require_relative "../tables/cff/index_builder"
require_relative "../tables/cff/dict_builder"
require_relative "../tables/glyf/glyph_builder"
require_relative "../tables/glyf/compound_glyph_resolver"
require_relative "../optimizers/pattern_analyzer"
require_relative "../optimizers/subroutine_optimizer"
require_relative "../optimizers/subroutine_builder"
require_relative "../optimizers/charstring_rewriter"
require_relative "../hints/truetype_hint_extractor"
require_relative "../hints/postscript_hint_extractor"
require_relative "../hints/hint_converter"
require_relative "../hints/truetype_hint_applier"
require_relative "../hints/postscript_hint_applier"
require_relative "../tables/cff2"
require_relative "../variation/data_extractor"
require_relative "../variation/instance_generator"
require_relative "../variation/converter"

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
    # - Optionally preserving rendering hints
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
    #
    # @example Converting with hint preservation
    #   converter = Fontisan::Converters::OutlineConverter.new
    #   otf_font = converter.convert(ttf_font, target_format: :otf, preserve_hints: true)
    class OutlineConverter
      include ConversionStrategy

      # Supported outline formats
      SUPPORTED_FORMATS = %i[ttf otf cff2].freeze

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
      # @option options [Boolean] :optimize_cff Enable CFF subroutine optimization (default: false)
      # @option options [Boolean] :preserve_hints Preserve rendering hints (default: false)
      # @option options [Boolean] :preserve_variations Keep variation data during conversion (default: true)
      # @option options [Boolean] :generate_instance Generate static instance instead of variable font (default: false)
      # @option options [Hash] :instance_coordinates Axis coordinates for instance generation (default: {})
      # @return [Hash<String, String>] Map of table tags to binary data
      def convert(font, options = {})
        @font = font
        @options = options
        @optimize_cff = options.fetch(:optimize_cff, false)
        @preserve_hints = options.fetch(:preserve_hints, false)
        @preserve_variations = options.fetch(:preserve_variations, true)
        @generate_instance = options.fetch(:generate_instance, false)
        @instance_coordinates = options.fetch(:instance_coordinates, {})
        target_format = options[:target_format] ||
          detect_target_format(font)
        validate(font, target_format)

        source_format = detect_format(font)

        # Check if we should generate a static instance instead
        if @generate_instance && variable_font?(font)
          return generate_static_instance(font, source_format, target_format)
        end

        case [source_format, target_format]
        when %i[ttf otf]
          convert_ttf_to_otf(font, options)
        when %i[otf ttf]
          convert_otf_to_ttf(font)
        when %i[cff2 ttf]
          # CFF2 to TTF - treat CFF2 similar to OTF for now
          convert_otf_to_ttf(font)
        when %i[ttf cff2]
          # TTF to CFF2 - for variable fonts
          convert_ttf_to_otf(font, options)
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
      def convert_ttf_to_otf(font, _options = {})
        # Extract all glyphs from glyf table
        outlines = extract_ttf_outlines(font)

        # Extract hints if preservation is enabled
        hints_per_glyph = @preserve_hints ? extract_ttf_hints(font) : {}

        # Build CFF table from outlines and hints
        cff_data = build_cff_table(outlines, font, hints_per_glyph)

        # Copy all tables except glyf/loca
        tables = copy_tables(font, %w[glyf loca])

        # Add CFF table
        tables["CFF "] = cff_data

        # Update maxp table for CFF
        tables["maxp"] = update_maxp_for_cff(font, outlines.length)

        # Update head table for CFF
        tables["head"] = update_head_for_cff(font)

        # Convert and apply hints if preservation is enabled
        if @preserve_hints && hints_per_glyph.any?
          # Extract font-level hints separately
          hint_set = extract_ttf_hint_set(font)

          unless hint_set.empty?
            # Convert TrueType hints to PostScript format
            converter = Hints::HintConverter.new
            ps_hint_set = converter.convert_hint_set(hint_set, :postscript)

            # Apply PostScript hints (validation mode - CFF modification pending)
            applier = Hints::PostScriptHintApplier.new
            tables = applier.apply(ps_hint_set, tables)
          end
        end

        tables
      end

      # Convert OpenType/CFF font to TrueType
      #
      # @param font [OpenTypeFont] Source font
      # @return [Hash<String, String>] Target tables
      def convert_otf_to_ttf(font)
        # Extract all glyphs from CFF table
        outlines = extract_cff_outlines(font)

        # Extract hints if preservation is enabled
        hints_per_glyph = @preserve_hints ? extract_cff_hints(font) : {}

        # Build glyf and loca tables
        glyf_data, loca_data, loca_format = build_glyf_loca_tables(outlines,
                                                                   hints_per_glyph)

        # Copy all tables except CFF
        tables = copy_tables(font, ["CFF ", "CFF2"])

        # Add glyf and loca tables
        tables["glyf"] = glyf_data
        tables["loca"] = loca_data

        # Update maxp table for TrueType
        tables["maxp"] = update_maxp_for_truetype(font, outlines, loca_format)

        # Update head table for TrueType
        tables["head"] = update_head_for_truetype(font, loca_format)

        # Convert and apply hints if preservation is enabled
        if @preserve_hints && hints_per_glyph.any?
          # Extract font-level hints separately
          hint_set = extract_cff_hint_set(font)

          unless hint_set.empty?
            # Convert PostScript hints to TrueType format
            converter = Hints::HintConverter.new
            tt_hint_set = converter.convert_hint_set(hint_set, :truetype)

            # Apply TrueType hints (writes fpgm/prep/cvt tables)
            applier = Hints::TrueTypeHintApplier.new
            tables = applier.apply(tt_hint_set, tables)
          end
        end

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
          %i[cff2 ttf],
          %i[ttf cff2],
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
      def build_cff_table(outlines, font, _hints_per_glyph)
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

        # Apply subroutine optimization if enabled
        local_subrs = []

        if @optimize_cff
          begin
            charstrings, local_subrs = optimize_charstrings(charstrings)
          rescue StandardError => e
            # If optimization fails, fall back to unoptimized CharStrings
            warn "CFF optimization failed: #{e.message}, using unoptimized CharStrings"
            local_subrs = []
          end
        end

        # Build font metadata
        begin
          font_name = extract_font_name(font)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to extract font name: #{e.message}"
        end

        # Build all INDEXes
        begin
          header_size = 4
          name_index_data = Tables::Cff::IndexBuilder.build([font_name])
          string_index_data = Tables::Cff::IndexBuilder.build([]) # Empty strings
          global_subr_index_data = Tables::Cff::IndexBuilder.build([]) # Empty global subrs
          charstrings_index_data = Tables::Cff::IndexBuilder.build(charstrings)
          local_subrs_index_data = Tables::Cff::IndexBuilder.build(local_subrs)
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build CFF indexes: #{e.message}"
        end

        # Build Private DICT with Subrs offset if we have local subroutines
        begin
          private_dict_hash = {
            default_width_x: 1000,
            nominal_width_x: 0,
          }

          # If we have local subroutines, add Subrs offset
          # Subrs offset is relative to Private DICT start
          if local_subrs.any?
            # Add a placeholder Subrs offset first to get accurate size
            private_dict_hash[:subrs] = 0

            # Calculate size of Private DICT with Subrs entry
            temp_private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
            subrs_offset = temp_private_dict_data.bytesize

            # Update with actual Subrs offset
            private_dict_hash[:subrs] = subrs_offset
          end

          # Build final Private DICT
          private_dict_data = Tables::Cff::DictBuilder.build(private_dict_hash)
          private_dict_size = private_dict_data.bytesize
        rescue StandardError => e
          raise Fontisan::Error, "Failed to build Private DICT: #{e.message}"
        end

        # Calculate offsets with iterative refinement
        begin
          # Initial pass
          top_dict_index_start = header_size + name_index_data.bytesize
          string_index_start = top_dict_index_start + 100 # Approximate
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize

          # Build Top DICT
          top_dict_hash = {
            charset: 0,
            encoding: 0,
            charstrings: charstrings_offset,
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

          # Recalculate with actual Top DICT size
          string_index_start = top_dict_index_start + top_dict_index_data.bytesize
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize
          private_dict_offset = charstrings_offset + charstrings_index_data.bytesize

          # Update Top DICT with Private DICT info
          top_dict_hash = {
            charset: 0,
            encoding: 0,
            charstrings: charstrings_offset,
            private: [private_dict_size, private_dict_offset],
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])

          # Final recalculation
          string_index_start = top_dict_index_start + top_dict_index_data.bytesize
          global_subr_index_start = string_index_start + string_index_data.bytesize
          charstrings_offset = global_subr_index_start + global_subr_index_data.bytesize
          private_dict_offset = charstrings_offset + charstrings_index_data.bytesize

          # Final Top DICT
          top_dict_hash = {
            charset: 0,
            encoding: 0,
            charstrings: charstrings_offset,
            private: [private_dict_size, private_dict_offset],
          }
          top_dict_data = Tables::Cff::DictBuilder.build(top_dict_hash)
          top_dict_index_data = Tables::Cff::IndexBuilder.build([top_dict_data])
        rescue StandardError => e
          raise Fontisan::Error,
                "Failed to calculate CFF table offsets: #{e.message}"
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
      def build_glyf_loca_tables(outlines, _hints_per_glyph)
        glyf_data = "".b
        offsets = []

        # Build each glyph
        outlines.each do |outline|
          offsets << glyf_data.bytesize

          if outline.empty?
            # Empty glyph - no data
            next
          end

          # Build glyph data using GlyphBuilder class method
          glyph_data = Fontisan::Tables::GlyphBuilder.build_simple_glyph(outline)
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
        ].pack("Nnnnnnnnnnnnnnn")
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

      # Optimize CharStrings using subroutine extraction
      #
      # @param charstrings [Array<String>] Original CharString bytes
      # @return [Array<Array<String>, Array<String>>] [optimized_charstrings, local_subrs]
      def optimize_charstrings(charstrings)
        # Convert to hash format expected by PatternAnalyzer
        charstrings_hash = {}
        charstrings.each_with_index do |cs, index|
          charstrings_hash[index] = cs
        end

        # Analyze patterns
        analyzer = Optimizers::PatternAnalyzer.new(
          min_length: 10,
          stack_aware: true,
        )
        patterns = analyzer.analyze(charstrings_hash)

        # Return original if no patterns found
        return [charstrings, []] if patterns.empty?

        # Optimize selection
        optimizer = Optimizers::SubroutineOptimizer.new(patterns,
                                                        max_subrs: 65_535)
        selected_patterns = optimizer.optimize_selection

        # Optimize ordering
        selected_patterns = optimizer.optimize_ordering(selected_patterns)

        # Return original if no patterns selected
        return [charstrings, []] if selected_patterns.empty?

        # Build subroutines
        builder = Optimizers::SubroutineBuilder.new(selected_patterns,
                                                    type: :local)
        local_subrs = builder.build

        # Build subroutine map
        subroutine_map = {}
        selected_patterns.each_with_index do |pattern, index|
          subroutine_map[pattern.bytes] = index
        end

        # Rewrite CharStrings
        rewriter = Optimizers::CharstringRewriter.new(subroutine_map, builder)
        optimized_charstrings = charstrings.map.with_index do |charstring, glyph_id|
          # Find patterns for this glyph
          glyph_patterns = selected_patterns.select do |p|
            p.glyphs.include?(glyph_id)
          end

          if glyph_patterns.empty?
            charstring
          else
            rewriter.rewrite(charstring, glyph_patterns)
          end
        end

        [optimized_charstrings, local_subrs]
      rescue StandardError => e
        # If optimization fails for any reason, return original CharStrings
        warn "Optimization warning: #{e.message}"
        [charstrings, []]
      end

      # Generate static instance from variable font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Variable font
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @return [Hash<String, String>] Static font tables
      def generate_static_instance(font, source_format, target_format)
        # Generate instance at specified coordinates
        fvar = font.table("fvar")
        fvar ? fvar.axes : []

        generator = Variation::InstanceGenerator.new(font,
                                                     @instance_coordinates)
        instance_tables = generator.generate

        # If target format differs from source, convert outlines
        if source_format == target_format
          instance_tables
        else
          # Create temporary font with instance tables
          temp_font = font.class.new
          temp_font.instance_variable_set(:@table_data, instance_tables)

          # Convert outline format
          case [source_format, target_format]
          when %i[ttf otf]
            convert_ttf_to_otf(temp_font, @options)
          when %i[otf ttf], %i[cff2 ttf]
            convert_otf_to_ttf(temp_font)
          else
            instance_tables
          end
        end
      end

      # Convert variation data during outline conversion
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @param target_format [Symbol] Target format
      # @return [Hash, nil] Converted variation data or nil
      def convert_variations(font, target_format)
        return nil unless @preserve_variations
        return nil unless variable_font?(font)

        fvar = font.table("fvar")
        return nil unless fvar

        axes = fvar.axes
        converter = Variation::Converter.new(font, axes)

        # Get glyph count
        maxp = font.table("maxp")
        return nil unless maxp

        glyph_count = maxp.num_glyphs

        # Convert variation data for each glyph
        variation_data = {}
        glyph_count.times do |glyph_id|
          source_format = detect_format(font)

          data = case [source_format, target_format]
                 when %i[ttf otf], %i[ttf cff2]
                   # gvar → blend
                   converter.gvar_to_blend(glyph_id)
                 when %i[otf ttf], %i[cff2 ttf]
                   # blend → gvar
                   converter.blend_to_gvar(glyph_id)
                 end

          variation_data[glyph_id] = data if data
        end

        variation_data.empty? ? nil : variation_data
      end

      # Detect font format from tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to detect
      # @return [Symbol] Format (:ttf, :otf, or :cff2)
      # @raise [Error] If format cannot be detected
      def detect_format(font)
        # Check for CFF2 table first (OpenType variable fonts with CFF2 outlines)
        if font.has_table?("CFF2")
          :cff2
        # Check for CFF table (OpenType/CFF)
        elsif font.has_table?("CFF ")
          :otf
        # Check for glyf table (TrueType)
        elsif font.has_table?("glyf")
          :ttf
        else
          raise Fontisan::Error,
                "Cannot detect font format: missing outline tables (CFF2, CFF, or glyf)"
        end
      end

      # Detect target format as opposite of source
      #
      # @param font [TrueTypeFont, OpenTypeFont] Source font
      # @return [Symbol] Target format
      def detect_target_format(font)
        source = detect_format(font)
        case source
        when :ttf
          :otf
        when :cff2
          :ttf
        else
          :ttf
        end
      end

      # Validate source font has required tables
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to validate
      # @param format [Symbol] Font format
      # @raise [Error] If required tables are missing
      def validate_source_tables(font, format)
        case format
        when :ttf
          unless font.has_table?("glyf") && font.has_table?("loca")
            raise Fontisan::MissingTableError,
                  "TrueType font missing required glyf or loca table"
          end
          # Also verify tables can actually be loaded
          unless font.table("glyf") && font.table("loca")
            raise Fontisan::MissingTableError,
                  "TrueType font missing required glyf or loca table"
          end
        when :cff2
          unless font.has_table?("CFF2")
            raise Fontisan::MissingTableError,
                  "CFF2 font missing required CFF2 table"
          end
          unless font.table("CFF2")
            raise Fontisan::MissingTableError,
                  "CFF2 font missing required CFF2 table"
          end
        when :otf
          unless font.has_table?("CFF ") || font.has_table?("CFF2")
            raise Fontisan::MissingTableError,
                  "OpenType font missing required CFF or CFF2 table"
          end
          # Verify at least one can be loaded
          unless font.table("CFF ") || font.table("CFF2")
            raise Fontisan::MissingTableError,
                  "OpenType font missing required CFF or CFF2 table"
          end
        end

        # Common required tables
        %w[head hhea maxp].each do |tag|
          unless font.has_table?(tag)
            raise Fontisan::MissingTableError,
                  "Font missing required #{tag} table"
          end
          # Verify table can actually be loaded
          unless font.table(tag)
            raise Fontisan::MissingTableError,
                  "Font missing required #{tag} table"
          end
        end
      end

      # Extract hints from TrueType font
      #
      # @param font [TrueTypeFont] Source font
      # @return [Hash<Integer, Array<Hint>>] Map of glyph ID to hints
      def extract_ttf_hints(font)
        hints_per_glyph = {}
        extractor = Hints::TrueTypeHintExtractor.new

        # Get required tables
        head = font.table("head")
        maxp = font.table("maxp")
        loca = font.table("loca")
        glyf = font.table("glyf")

        # Parse loca with context
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)

        # Extract hints from each glyph
        maxp.num_glyphs.times do |glyph_id|
          glyph = glyf.glyph_for(glyph_id, loca, head)
          next if glyph.nil? || glyph.empty?

          hints = extractor.extract(glyph)
          hints_per_glyph[glyph_id] = hints if hints.any?
        end

        hints_per_glyph
      rescue StandardError => e
        warn "Failed to extract TrueType hints: #{e.message}"
        {}
      end

      # Extract hints from CFF font
      #
      # @param font [OpenTypeFont] Source font
      # @return [Hash<Integer, Array<Hint>>] Map of glyph ID to hints
      def extract_cff_hints(font)
        hints_per_glyph = {}
        extractor = Hints::PostScriptHintExtractor.new

        # Get CFF table
        cff = font.table("CFF ")
        return {} unless cff

        # Get number of glyphs
        num_glyphs = cff.glyph_count

        # Extract hints from each CharString
        num_glyphs.times do |glyph_id|
          charstring = cff.charstring_for_glyph(glyph_id)
          next if charstring.nil?

          hints = extractor.extract(charstring)
          hints_per_glyph[glyph_id] = hints if hints.any?
        end

        hints_per_glyph
      rescue StandardError => e
        warn "Failed to extract CFF hints: #{e.message}"
        {}
      end

      # Extract complete TrueType hint set from font
      #
      # @param font [TrueTypeFont] Source font
      # @return [HintSet] Complete hint set
      def extract_ttf_hint_set(font)
        extractor = Hints::TrueTypeHintExtractor.new
        extractor.extract_from_font(font)
      rescue StandardError => e
        warn "Failed to extract TrueType hint set: #{e.message}"
        Models::HintSet.new(format: :truetype)
      end

      # Extract complete PostScript hint set from font
      #
      # @param font [OpenTypeFont] Source font
      # @return [HintSet] Complete hint set
      def extract_cff_hint_set(font)
        extractor = Hints::PostScriptHintExtractor.new
        extractor.extract_from_font(font)
      rescue StandardError => e
        warn "Failed to extract PostScript hint set: #{e.message}"
        Models::HintSet.new(format: :postscript)
      end

      # Check if font is a variable font
      #
      # @param font [TrueTypeFont, OpenTypeFont] Font to check
      # @return [Boolean] True if font has variation tables
      def variable_font?(font)
        font.has_table?("fvar")
      end
    end
  end
end
