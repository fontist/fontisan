# frozen_string_literal: true

module Fontisan
  module Commands
    # Command to list glyph names from a font file
    #
    # Retrieves glyph names from the post table. Different post table versions
    # provide different levels of glyph name information:
    # - Version 1.0: Standard 258 Mac glyph names
    # - Version 2.0: Custom glyph names
    # - Version 3.0+: No glyph names
    #
    # @example List glyph names from a font
    #   command = GlyphsCommand.new("font.ttf")
    #   result = command.run
    #   puts result.glyph_count
    class GlyphsCommand < BaseCommand
      # Execute the command to retrieve glyph names
      #
      # @return [Models::GlyphInfo] Information about glyphs in the font
      def run
        glyph_info = Models::GlyphInfo.new

        # Try to get glyph names from post table first
        if font.has_table?(Constants::POST_TAG)
          post_table = font.table(Constants::POST_TAG)
          names = post_table.glyph_names

          if names&.any?
            glyph_info.glyph_names = names
            glyph_info.glyph_count = names.length
            glyph_info.source = "post_#{post_table.version}"
            return glyph_info
          end
        end

        # Future: Try CFF table if no post table or no names
        # if font.has_table?('CFF ')
        #   # Get names from CFF
        # end

        # No glyph name information available
        glyph_info.glyph_names = []
        glyph_info.glyph_count = 0
        glyph_info.source = "none"
        glyph_info
      end
    end
  end
end
