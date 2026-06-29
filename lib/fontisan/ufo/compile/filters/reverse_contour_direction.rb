# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Reverses the point order in every contour. TrueType fonts
        # use clockwise winding for outer contours (opposite of the
        # PostScript/UFO convention). Applying this filter before
        # TTF compilation ensures correct glyph rendering.
        module ReverseContourDirection
          # @param glyphs [Array<Fontisan::Ufo::Glyph>]
          # @return [Array<Fontisan::Ufo::Glyph>] the same array,
          #   mutated in place
          def self.run(glyphs, **_opts)
            glyphs.each do |glyph|
              glyph.contours.each do |contour|
                contour.points.reverse!
              end
            end
            glyphs
          end
        end
      end
    end
  end
end
