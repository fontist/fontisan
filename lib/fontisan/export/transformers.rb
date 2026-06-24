# frozen_string_literal: true

# Autoload hub for the Fontisan::Export::Transformers namespace.

module Fontisan
  module Export
    module Transformers
      autoload :FontToTtx, "fontisan/export/transformers/font_to_ttx"
      autoload :HeadTransformer, "fontisan/export/transformers/head_transformer"
      autoload :HheaTransformer, "fontisan/export/transformers/hhea_transformer"
      autoload :MaxpTransformer, "fontisan/export/transformers/maxp_transformer"
      autoload :NameTransformer, "fontisan/export/transformers/name_transformer"
      autoload :Os2Transformer, "fontisan/export/transformers/os2_transformer"
      autoload :PostTransformer, "fontisan/export/transformers/post_transformer"
    end
  end
end
