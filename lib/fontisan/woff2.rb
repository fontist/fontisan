# frozen_string_literal: true

# Autoload hub for the Fontisan::Woff2 namespace.

module Fontisan
  module Woff2
    autoload :Directory, "fontisan/woff2/directory"
    autoload :GlyfTransformer, "fontisan/woff2/glyf_transformer"
    autoload :HmtxTransformer, "fontisan/woff2/hmtx_transformer"
    autoload :TableTransformer, "fontisan/woff2/table_transformer"
    autoload :Woff2Header, "fontisan/woff2/header"
  end
end
