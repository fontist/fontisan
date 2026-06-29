# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Decomposes composite glyphs (those with Components) into
        # simple glyphs by resolving each component reference to its
        # base glyph's contours and applying the component's
        # transformation matrix.
        #
        # For MVP: components are silently dropped (the glyph retains
        # its own contours but loses component-derived outlines).
        # Full resolution requires the full glyph-name → glyph lookup
        # that the compiler provides. TODO.full/07b will wire this.
        module DecomposeComponents
          def self.run(glyphs, **_opts)
            glyphs.each do |glyph|
              # Drop components; keep contours only.
              # Full implementation would:
              #   1. Look up each component's base glyph by name
              #   2. Clone its contours
              #   3. Apply the component's Transformation matrix
              #   4. Merge into this glyph's contours
              glyph.components.clear
            end
            glyphs
          end
        end
      end
    end
  end
end
