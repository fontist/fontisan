# frozen_string_literal: true

# Autoload hub for the Fontisan::Converters namespace.

module Fontisan
  module Converters
    autoload :CffTableBuilder, "fontisan/converters/cff_table_builder"
    autoload :CollectionConverter, "fontisan/converters/collection_converter"
    autoload :ConversionStrategy, "fontisan/converters/conversion_strategy"
    autoload :FormatConverter, "fontisan/converters/format_converter"
    autoload :GlyfTableBuilder, "fontisan/converters/glyf_table_builder"
    autoload :OutlineConverter, "fontisan/converters/outline_converter"
    autoload :OutlineExtraction, "fontisan/converters/outline_extraction"
    autoload :OutlineOptimizer, "fontisan/converters/outline_optimizer"
    autoload :SvgGenerator, "fontisan/converters/svg_generator"
    autoload :TableCopier, "fontisan/converters/table_copier"
    autoload :Type1Converter, "fontisan/converters/type1_converter"
    autoload :Woff2Encoder, "fontisan/converters/woff2_encoder"
    autoload :WoffWriter, "fontisan/converters/woff_writer"
  end
end
