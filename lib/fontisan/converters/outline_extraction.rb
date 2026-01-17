# frozen_string_literal: true

require_relative "../outline_extractor"
require_relative "../tables/cff/charstring_builder"
require_relative "../tables/glyf/glyph_builder"
require_relative "../tables/glyf/compound_glyph_resolver"

module Fontisan
  module Converters
    # Extracts all glyph outlines from a font for conversion purposes
    #
    # Unlike [`OutlineExtractor`](../outline_extractor.rb) which extracts
    # single glyphs, this module extracts ALL glyphs from a font for
    # bulk conversion operations.
    #
    # @see OutlineExtractor for single glyph extraction
    module OutlineExtraction
      # Extract all outlines from TrueType font
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

      # Extract all outlines from CFF font
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
    end
  end
end
