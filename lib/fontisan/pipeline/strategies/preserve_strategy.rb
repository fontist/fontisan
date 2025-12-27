# frozen_string_literal: true

require_relative "base_strategy"

module Fontisan
  module Pipeline
    module Strategies
      # Strategy for preserving variation data during conversion
      #
      # This strategy maintains all variation tables intact, making it suitable
      # for conversions between compatible formats:
      # - Variable TTF → Variable TTF (same format)
      # - Variable OTF → Variable OTF (same format)
      # - Variable TTF → Variable WOFF/WOFF2 (packaging change only)
      # - Variable OTF → Variable WOFF/WOFF2 (packaging change only)
      #
      # The strategy copies all font tables including:
      # - Variation tables: fvar, gvar/CFF2, avar, HVAR, VVAR, MVAR
      # - Base tables: All non-variation tables
      #
      # @example Preserve variation data
      #   strategy = PreserveStrategy.new
      #   tables = strategy.resolve(variable_font)
      #   # tables includes fvar, gvar, etc.
      class PreserveStrategy < BaseStrategy
        # Resolve by preserving all variation data
        #
        # Returns all font tables including variation tables. This is a simple
        # copy operation that maintains the variable font's full capabilities.
        #
        # @param font [TrueTypeFont, OpenTypeFont] Variable font
        # @return [Hash<String, String>] All font tables
        def resolve(font)
          # Return a copy of all font tables
          # This preserves variation tables (fvar, gvar, CFF2, avar, HVAR, etc.)
          # and all base tables
          font.table_data.dup
        end

        # Check if strategy preserves variation data
        #
        # @return [Boolean] Always true for this strategy
        def preserves_variation?
          true
        end

        # Get strategy name
        #
        # @return [Symbol] :preserve
        def strategy_name
          :preserve
        end
      end
    end
  end
end
