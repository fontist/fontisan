# frozen_string_literal: true

require_relative "../tables/glyf/glyph_builder"

module Fontisan
  module Converters
    # Builds glyf and loca tables from glyph outlines
    #
    # This module handles the construction of TrueType glyph tables:
    # - glyf table: Contains actual glyph outline data
    # - loca table: Contains offsets to glyph data in glyf table
    #
    # The loca table format depends on the maximum offset:
    # - Short format (offsets/2) if max offset <= 0x1FFFE
    # - Long format (raw offsets) if max offset > 0x1FFFE
    module GlyfTableBuilder
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
    end
  end
end
