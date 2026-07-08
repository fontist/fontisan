# frozen_string_literal: true

# Autoload hub for the Fontisan::Subset namespace.

module Fontisan
  module Subset
    autoload :Builder, "fontisan/subset/builder"
    autoload :GlyphMapping, "fontisan/subset/glyph_mapping"
    autoload :Options, "fontisan/subset/options"
    autoload :Profile, "fontisan/subset/profile"
    autoload :SharedState, "fontisan/subset/shared_state"
    autoload :SubsetContext, "fontisan/subset/subset_context"
    autoload :TableStrategy, "fontisan/subset/table_strategy"
    autoload :TableSubsetter, "fontisan/subset/table_subsetter"
  end
end
