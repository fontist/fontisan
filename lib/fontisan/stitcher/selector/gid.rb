# frozen_string_literal: true

module Fontisan
  class Stitcher
    module Selector
      # Include a single glyph by its donor gid. Used for unencoded
      # glyphs (.notdef, spaces, format-specific specials).
      class Gid
        attr_reader :gid

        def initialize(gid)
          @gid = gid
        end

        def apply(source, bindings)
          bindings << {
            codepoint: nil,
            source: source,
            donor_gid: @gid,
          }
        end
      end
    end
  end
end
