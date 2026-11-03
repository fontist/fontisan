# frozen_string_literal: true

# Autoload hub for the Fontisan::Variation::Instancing namespace.

module Fontisan
  module Variation
    # Static instancing of TrueType variable fonts: gvar/HVAR delta
    # application, glyf/hmtx rebuilding and OS/2 + name updates.
    module Instancing
      autoload :AxisSpace, "fontisan/variation/instancing/axis_space"
      autoload :GlyphOutline, "fontisan/variation/instancing/glyph_outline"
      autoload :GvarReader, "fontisan/variation/instancing/gvar_reader"
      autoload :ItemVariationStore,
               "fontisan/variation/instancing/item_variation_store"
      autoload :NameRewriter, "fontisan/variation/instancing/name_rewriter"
      autoload :TrueTypeInstancer,
               "fontisan/variation/instancing/true_type_instancer"
    end
  end
end
