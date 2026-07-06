# frozen_string_literal: true

# Autoload hub for the Fontisan::Woff2 namespace.

module Fontisan
  module Woff2
    autoload :CollectionEncoder, "fontisan/woff2/collection_encoder"
    autoload :Directory, "fontisan/woff2/directory"
    autoload :EncoderRules, "fontisan/woff2/encoder_rules"
    autoload :GlyfLocaReconstruct, "fontisan/woff2/glyf_loca_reconstruct"
    autoload :GlyfLocaTransform, "fontisan/woff2/glyf_loca_transform"
    autoload :HmtxTransformer, "fontisan/woff2/hmtx_transformer"
    autoload :TableTransformer, "fontisan/woff2/table_transformer"
    autoload :TripletCodec, "fontisan/woff2/triplet_codec"
    autoload :Woff2Header, "fontisan/woff2/header"
  end
end
