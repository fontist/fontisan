# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module Filters
        # Flattens nested component references. If glyph A references
        # glyph B which references glyph C, this filter makes A
        # directly reference C (one level deep only).
        #
        # For MVP: same as DecomposeComponents — components are
        # cleared. Full implementation lands with TODO.full/07b.
        module FlattenComponents
          def self.run(glyphs, **_opts)
            glyphs.each { |g| g.components.clear }
            glyphs
          end
        end
      end
    end
  end
end
