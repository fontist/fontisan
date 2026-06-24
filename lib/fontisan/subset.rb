# frozen_string_literal: true

# Autoload hub for the Fontisan::Subset namespace.

module Fontisan
  module Subset
    autoload :Builder, "fontisan/subset/builder"
    autoload :GlyphMapping, "fontisan/subset/glyph_mapping"
    autoload :Options, "fontisan/subset/options"
    autoload :Profile, "fontisan/subset/profile"
    autoload :TableSubsetter, "fontisan/subset/table_subsetter"
  end
end
