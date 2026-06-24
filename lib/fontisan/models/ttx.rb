# frozen_string_literal: true

# Autoload hub for the Fontisan::Models::Ttx namespace.

module Fontisan
  module Models
    module Ttx
      autoload :GlyphId, "fontisan/models/ttx/glyph_order"
      autoload :GlyphOrder, "fontisan/models/ttx/glyph_order"
      autoload :Tables, "fontisan/models/ttx/tables/os2_table"
      autoload :TtFont, "fontisan/models/ttx/ttfont"
    end
  end
end
