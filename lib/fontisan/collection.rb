# frozen_string_literal: true

# Autoload hub for the Fontisan::Collection namespace.

module Fontisan
  module Collection
    autoload :Builder, "fontisan/collection/builder"
    autoload :DfontBuilder, "fontisan/collection/dfont_builder"
    autoload :OffsetCalculator, "fontisan/collection/offset_calculator"
    autoload :SharedLogic, "fontisan/collection/shared_logic"
    autoload :TableAnalyzer, "fontisan/collection/table_analyzer"
    autoload :TableDeduplicator, "fontisan/collection/table_deduplicator"
    autoload :Writer, "fontisan/collection/writer"
  end
end
