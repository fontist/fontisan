# frozen_string_literal: true

# Autoload hub for the Fontisan::Export namespace.

module Fontisan
  module Export
    autoload :Exporter, "fontisan/export/exporter"
    autoload :TableSerializer, "fontisan/export/table_serializer"
    autoload :Transformers, "fontisan/export/transformers/font_to_ttx"
    autoload :TtxGenerator, "fontisan/export/ttx_generator"
    autoload :TtxParser, "fontisan/export/ttx_parser"
  end
end
