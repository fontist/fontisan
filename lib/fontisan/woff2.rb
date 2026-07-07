# frozen_string_literal: true

# Autoload hub for the Fontisan::Woff2 namespace.

module Fontisan
  module Woff2
    autoload :CollectionDecoder, "fontisan/woff2/collection_decoder"
    autoload :CollectionEncoder, "fontisan/woff2/collection_encoder"
    autoload :Directory, "fontisan/woff2/directory"
    autoload :EncoderRules, "fontisan/woff2/encoder_rules"
    autoload :GlyfCanonicalizer, "fontisan/woff2/glyf_canonicalizer"
    autoload :GlyfLocaReconstruct, "fontisan/woff2/glyf_loca_reconstruct"
    autoload :GlyfLocaTransform, "fontisan/woff2/glyf_loca_transform"
    autoload :HmtxTransformer, "fontisan/woff2/hmtx_transformer"
    autoload :SfntChecksum, "fontisan/woff2/sfnt_checksum"
    autoload :TableTransformer, "fontisan/woff2/table_transformer"
    autoload :TripletCodec, "fontisan/woff2/triplet_codec"
    autoload :UInt255, "fontisan/woff2/uint255"
    autoload :Woff2Header, "fontisan/woff2/header"
  end
end
