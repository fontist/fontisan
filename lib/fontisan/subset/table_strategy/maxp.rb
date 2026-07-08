# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Maxp strategy: rewrite numGlyphs (offset 4, uint16) to the
      # subset's glyph count. The remaining maxp fields describe worst-
      # case outline/instruction complexity and can be left as-is —
      # a smaller subset cannot exceed the source's maxima.
      class Maxp
        # @param context [SubsetContext]
        # @param tag [String] "maxp"
        # @param table [Maxp] parsed maxp table
        # @return [String] binary maxp bytes for the subset
        def self.call(context:, tag:, table:)
          data = table.to_binary_s.dup
          data[4, 2] = [context.mapping.size].pack("n")
          data
        end
      end
    end
  end
end
