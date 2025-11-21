# frozen_string_literal: true

module Fontisan
  # High-level utility class for unified glyph access across font formats
  #
  # [`GlyphAccessor`](lib/fontisan/glyph_accessor.rb) provides a clean, unified
  # interface for accessing glyphs regardless of the underlying font format
  # (TrueType with glyf table or OpenType with CFF table).
  #
  # This class automatically detects the font format and delegates to the
  # appropriate table parser, abstracting away the complexity of different
  # glyph storage mechanisms.
  #
  # Key features:
  # - Unified glyph access by ID, Unicode character, or PostScript name
  # - Automatic format detection (TrueType glyf vs CFF)
  # - Metrics retrieval (advance width, left sidebearing)
  # - Glyph closure calculation for subsetting (tracks composite dependencies)
  # - Validation of glyph IDs and character mappings
  #
  # @example Basic usage
  #   font = Fontisan::TrueTypeFont.from_file('font.ttf')
  #   accessor = Fontisan::GlyphAccessor.new(font)
  #
  #   # Access glyph by ID
  #   glyph = accessor.glyph_for_id(42)
  #   puts glyph.class  # => SimpleGlyph or CompoundGlyph
  #
  #   # Access glyph by Unicode character
  #   glyph_a = accessor.glyph_for_char(0x0041)  # 'A'
  #
  #   # Get metrics
  #   metrics = accessor.metrics_for_id(42)
  #   puts "Width: #{metrics[:advance_width]}, LSB: #{metrics[:lsb]}"
  #
  # @example Subsetting workflow with closure
  #   # Calculate all glyphs needed (including composite dependencies)
  #   base_glyphs = [0, 1, 65, 66, 67]  # .notdef, A, B, C
  #   all_glyphs = accessor.closure_for(base_glyphs)
  #   puts "Total glyphs needed: #{all_glyphs.size}"
  #
  # Reference: [`docs/ttfunk-feature-analysis.md:541-575`](docs/ttfunk-feature-analysis.md:541)
  class GlyphAccessor
    # Font instance this accessor operates on
    # @return [TrueTypeFont, OpenTypeFont]
    attr_reader :font

    # Initialize a new glyph accessor
    #
    # @param font [TrueTypeFont, OpenTypeFont] Font instance to access
    # @raise [ArgumentError] If font is nil or doesn't respond to table method
    def initialize(font)
      raise ArgumentError, "Font cannot be nil" if font.nil?

      unless font.respond_to?(:table)
        raise ArgumentError, "Font must respond to :table method"
      end

      @font = font
      @glyph_cache = {}
      @closure_cache = {}
    end

    # Get glyph object for a glyph ID
    #
    # Returns the appropriate glyph object based on the font format:
    # - TrueType fonts: [`SimpleGlyph`](lib/fontisan/tables/glyf/simple_glyph.rb)
    #   or [`CompoundGlyph`](lib/fontisan/tables/glyf/compound_glyph.rb)
    # - CFF fonts: [`CFFGlyph`](lib/fontisan/tables/cff/cff_glyph.rb)
    #
    # @param glyph_id [Integer] Glyph ID (0-based, 0 is .notdef)
    # @return [SimpleGlyph, CompoundGlyph, CFFGlyph, nil] Glyph object or nil
    #   if glyph is empty or invalid
    # @raise [ArgumentError] If glyph_id is invalid
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Get a glyph
    #   glyph = accessor.glyph_for_id(65)
    #   if glyph
    #     puts "Bounding box: #{glyph.bounding_box}"
    #     puts "Type: #{glyph.simple? ? 'simple' : 'compound'}"
    #   end
    def glyph_for_id(glyph_id)
      validate_glyph_id!(glyph_id)

      return @glyph_cache[glyph_id] if @glyph_cache.key?(glyph_id)

      glyph = if truetype?
                truetype_glyph(glyph_id)
              elsif cff?
                cff_glyph(glyph_id)
              else
                raise Fontisan::MissingTableError,
                      "Font has neither glyf nor CFF table"
              end

      @glyph_cache[glyph_id] = glyph
    end

    # Get glyph object for a Unicode character code
    #
    # Uses the cmap table to map the character code to a glyph ID,
    # then retrieves the corresponding glyph.
    #
    # @param char_code [Integer] Unicode character code (e.g., 0x0041 for 'A')
    # @return [SimpleGlyph, CompoundGlyph, nil] Glyph object or nil if
    #   character is not mapped
    # @raise [Fontisan::MissingTableError] If cmap table is missing
    #
    # @example Get glyph for 'A'
    #   glyph_a = accessor.glyph_for_char(0x0041)
    #   glyph_a = accessor.glyph_for_char('A'.ord)  # Equivalent
    def glyph_for_char(char_code)
      glyph_id = char_to_glyph_id(char_code)
      return nil unless glyph_id

      glyph_for_id(glyph_id)
    end

    # Get glyph object for a PostScript glyph name
    #
    # Uses the post table (if available) to map the glyph name to a glyph ID.
    # This method is primarily useful for fonts with post table version 2.0.
    #
    # @param glyph_name [String] PostScript glyph name (e.g., "A", "Aacute")
    # @return [SimpleGlyph, CompoundGlyph, nil] Glyph object or nil if
    #   name is not found
    # @raise [Fontisan::MissingTableError] If post table is missing or
    #   unsupported version
    #
    # @example Get glyph by name
    #   glyph = accessor.glyph_for_name("A")
    #   glyph = accessor.glyph_for_name("Aacute")
    def glyph_for_name(glyph_name)
      glyph_id = name_to_glyph_id(glyph_name)
      return nil unless glyph_id

      glyph_for_id(glyph_id)
    end

    # Get horizontal metrics for a glyph ID
    #
    # Returns a hash with advance width and left sidebearing in font units.
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [Hash{Symbol => Integer}, nil] Hash with :advance_width and
    #   :lsb keys, or nil if glyph is invalid
    # @raise [Fontisan::MissingTableError] If hmtx table is missing or not parsed
    #
    # @example Get metrics
    #   metrics = accessor.metrics_for_id(65)  # 'A'
    #   puts "Advance width: #{metrics[:advance_width]} FUnits"
    #   puts "Left sidebearing: #{metrics[:lsb]} FUnits"
    def metrics_for_id(glyph_id)
      validate_glyph_id!(glyph_id)

      hmtx = font.table("hmtx")
      raise_missing_table!("hmtx") unless hmtx

      unless hmtx.parsed?
        # Auto-parse if not already parsed
        parse_hmtx_with_context!(hmtx)
      end

      hmtx.metric_for(glyph_id)
    end

    # Get horizontal metrics for a Unicode character
    #
    # @param char_code [Integer] Unicode character code
    # @return [Hash{Symbol => Integer}, nil] Metrics hash or nil if not mapped
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Get metrics for 'A'
    #   metrics = accessor.metrics_for_char(0x0041)
    def metrics_for_char(char_code)
      glyph_id = char_to_glyph_id(char_code)
      return nil unless glyph_id

      metrics_for_id(glyph_id)
    end

    # Get outline for glyph by ID
    #
    # Extracts the complete outline data for a glyph, including all contours,
    # points, and bounding box information. The outline can be converted to
    # SVG paths or drawing commands for rendering.
    #
    # This method uses [`OutlineExtractor`](lib/fontisan/outline_extractor.rb)
    # to handle both TrueType (glyf) and CFF outline formats transparently.
    # For compound glyphs, it recursively resolves component dependencies.
    #
    # @param glyph_id [Integer] Glyph ID (0-based, 0 is .notdef)
    # @return [Models::GlyphOutline, nil] Outline object or nil if glyph is
    #   empty or invalid
    # @raise [ArgumentError] If glyph_id is invalid
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Get outline for a glyph
    #   outline = accessor.outline_for_id(65)  # 'A'
    #   if outline
    #     puts "Contours: #{outline.contour_count}"
    #     puts "Points: #{outline.point_count}"
    #     puts "SVG: #{outline.to_svg_path}"
    #   end
    def outline_for_id(glyph_id)
      extractor = OutlineExtractor.new(@font)
      extractor.extract(glyph_id)
    end

    # Get outline for Unicode codepoint
    #
    # Maps a Unicode codepoint to a glyph ID via the cmap table, then
    # extracts the outline for that glyph.
    #
    # @param codepoint [Integer] Unicode codepoint (e.g., 0x0041 for 'A')
    # @return [Models::GlyphOutline, nil] Outline object or nil if character
    #   is not mapped or glyph is empty
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Get outline for 'A'
    #   outline = accessor.outline_for_codepoint(0x0041)
    #   svg_path = outline.to_svg_path if outline
    def outline_for_codepoint(codepoint)
      glyph_id = char_to_glyph_id(codepoint)
      return nil unless glyph_id

      outline_for_id(glyph_id)
    end

    # Get outline for character
    #
    # Convenience method that takes a character string and extracts its
    # outline. The character is converted to its Unicode codepoint first.
    #
    # @param char [String] Single character (e.g., 'A', '中', '😀')
    # @return [Models::GlyphOutline, nil] Outline object or nil if character
    #   is not mapped or glyph is empty
    # @raise [ArgumentError] If char is not a single character
    # @raise [Fontisan::MissingTableError] If required tables are missing
    #
    # @example Get outline for 'A'
    #   outline = accessor.outline_for_char('A')
    #   commands = outline.to_commands if outline
    #
    # @example Handle multi-codepoint characters
    #   outline = accessor.outline_for_char('A')  # Works
    #   outline = accessor.outline_for_char('AB') # ArgumentError
    def outline_for_char(char)
      unless char.is_a?(String) && char.length == 1
        raise ArgumentError,
              "char must be a single character String, got: #{char.inspect}"
      end

      outline_for_codepoint(char.ord)
    end

    # Check if a glyph ID exists and is valid
    #
    # @param glyph_id [Integer] Glyph ID to check
    # @return [Boolean] True if glyph ID is valid
    def glyph_exists?(glyph_id)
      return false if glyph_id.nil? || glyph_id.negative?

      maxp = font.table("maxp")
      return false unless maxp

      glyph_id < maxp.num_glyphs
    end

    # Check if a Unicode character is mapped in the font
    #
    # @param char_code [Integer] Unicode character code
    # @return [Boolean] True if character has a glyph mapping
    def has_glyph_for_char?(char_code)
      !char_to_glyph_id(char_code).nil?
    end

    # Check if font uses TrueType outlines (glyf table)
    #
    # @return [Boolean] True if font has glyf table
    def truetype?
      font.table("glyf") != nil
    end

    # Check if font uses CFF outlines (CFF table)
    #
    # @return [Boolean] True if font has CFF table
    def cff?
      font.table("CFF ") != nil
    end

    # Calculate glyph closure for subsetting
    #
    # This method recursively tracks all glyphs needed for a given set of
    # glyph IDs, including component glyphs referenced by compound glyphs.
    # This is essential for font subsetting to ensure all required glyphs
    # are included.
    #
    # The closure always includes glyph 0 (.notdef) as required by the
    # OpenType specification.
    #
    # @param glyph_ids [Array<Integer>] Base set of glyph IDs
    # @return [Set<Integer>] Complete set of glyph IDs needed (including
    #   composite dependencies)
    # @raise [ArgumentError] If glyph_ids is not an array
    #
    # @example Calculate closure for subsetting
    #   # Want to subset to just "ABC"
    #   base_glyphs = [65, 66, 67]  # Assuming these are glyph IDs for A, B, C
    #   all_needed = accessor.closure_for(base_glyphs)
    #   # all_needed includes base glyphs + any composite dependencies + .notdef
    #
    # @example Closure with composite glyphs
    #   # If 'Ä' (glyph 100) is composite referencing 'A' (glyph 65) and
    #   # dieresis (glyph 200)
    #   closure = accessor.closure_for([100])
    #   # Returns: [0, 100, 65, 200]  (includes .notdef, Ä, A, dieresis)
    def closure_for(glyph_ids)
      unless glyph_ids.is_a?(Array)
        raise ArgumentError, "glyph_ids must be an Array"
      end

      # Start with provided glyphs plus .notdef
      result = Set.new([0])
      glyph_ids.each { |id| result.add(id) if glyph_exists?(id) }

      # CFF fonts have no composite glyphs, so return early
      return result if cff?

      # Recursively collect composite dependencies (TrueType only)
      to_process = result.to_a.dup
      processed = Set.new

      while (glyph_id = to_process.shift)
        next if processed.include?(glyph_id)

        processed.add(glyph_id)

        # Get glyph and check if it's compound
        glyph = glyph_for_id(glyph_id)
        next unless glyph
        next unless glyph.respond_to?(:compound?) && glyph.compound?

        # Add component glyph IDs
        if glyph.respond_to?(:components)
          glyph.components.each do |component|
            component_id = component[:glyph_index]
            next unless glyph_exists?(component_id)

            unless result.include?(component_id)
              result.add(component_id)
              to_process << component_id
            end
          end
        end
      end

      result
    end

    # Clear internal caches to free memory
    #
    # Useful for long-running processes that access many glyphs.
    #
    # @return [void]
    def clear_cache
      @glyph_cache.clear
      @closure_cache.clear

      # Also clear glyf table cache if present
      glyf = font.table("glyf")
      glyf&.clear_cache if glyf.respond_to?(:clear_cache)
    end

    private

    # Validate a glyph ID
    #
    # @param glyph_id [Integer] Glyph ID to validate
    # @raise [ArgumentError] If glyph ID is invalid
    def validate_glyph_id!(glyph_id)
      if glyph_id.nil?
        raise ArgumentError, "glyph_id cannot be nil"
      end

      if glyph_id.negative?
        raise ArgumentError, "glyph_id must be >= 0, got: #{glyph_id}"
      end

      unless glyph_exists?(glyph_id)
        maxp = font.table("maxp")
        num_glyphs = maxp ? maxp.num_glyphs : "unknown"
        raise ArgumentError,
              "glyph_id #{glyph_id} exceeds number of glyphs (#{num_glyphs})"
      end
    end

    # Get TrueType glyph from glyf table
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [SimpleGlyph, CompoundGlyph, nil] Glyph object
    def truetype_glyph(glyph_id)
      glyf = font.table("glyf")
      raise_missing_table!("glyf") unless glyf

      loca = font.table("loca")
      raise_missing_table!("loca") unless loca

      head = font.table("head")
      raise_missing_table!("head") unless head

      # Ensure loca is parsed
      unless loca.parsed?
        parse_loca_with_context!(loca, head)
      end

      glyf.glyph_for(glyph_id, loca, head)
    end

    # Get CFF glyph from CFF table
    #
    # @param glyph_id [Integer] Glyph ID
    # @return [CFFGlyph, nil] CFF glyph object or nil if empty
    def cff_glyph(glyph_id)
      cff = font.table(Constants::CFF_TAG)
      raise_missing_table!(Constants::CFF_TAG) unless cff

      # Get CharString for glyph
      charstring = cff.charstring_for_glyph(glyph_id)
      return nil unless charstring

      # Get Charset and Encoding
      charset = cff.charset
      encoding = cff.encoding

      # Wrap in CFFGlyph class
      Tables::Cff::CFFGlyph.new(glyph_id, charstring, charset, encoding)
    rescue StandardError => e
      warn "Failed to get CFF glyph #{glyph_id}: #{e.message}"
      nil
    end

    # Map character code to glyph ID
    #
    # @param char_code [Integer] Unicode character code
    # @return [Integer, nil] Glyph ID or nil if not mapped
    def char_to_glyph_id(char_code)
      cmap = font.table("cmap")
      raise_missing_table!("cmap") unless cmap

      cmap.unicode_mappings[char_code]
    end

    # Map glyph name to glyph ID
    #
    # @param glyph_name [String] PostScript glyph name
    # @return [Integer, nil] Glyph ID or nil if not found
    def name_to_glyph_id(glyph_name)
      post = font.table("post")
      raise_missing_table!("post") unless post

      # post.glyph_names returns array of names indexed by glyph ID
      names = post.glyph_names
      return nil if names.empty?

      names.index(glyph_name)
    end

    # Parse loca table with context
    #
    # @param loca [Loca] Loca table instance
    # @param head [Head] Head table instance
    def parse_loca_with_context!(loca, head)
      maxp = font.table("maxp")
      raise_missing_table!("maxp") unless maxp

      loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs)
    end

    # Parse hmtx table with context
    #
    # @param hmtx [Hmtx] Hmtx table instance
    def parse_hmtx_with_context!(hmtx)
      hhea = font.table("hhea")
      raise_missing_table!("hhea") unless hhea

      maxp = font.table("maxp")
      raise_missing_table!("maxp") unless maxp

      hmtx.parse_with_context(hhea.number_of_h_metrics, maxp.num_glyphs)
    end

    # Raise MissingTableError
    #
    # @param table_tag [String] Table tag
    # @raise [Fontisan::MissingTableError]
    def raise_missing_table!(table_tag)
      raise Fontisan::MissingTableError,
            "Required table '#{table_tag}' not found in font"
    end
  end
end
