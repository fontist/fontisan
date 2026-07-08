# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Name strategy: name records don't reference glyph IDs, so the
      # full source table is preserved.
      class Name
        # @param context [SubsetContext]
        # @param tag [String] "name"
        # @param table [Name] parsed name table (unused)
        # @return [String] source name bytes verbatim
        def self.call(context:, tag:, table:)
          context.font.table_data[tag]
        end
      end
    end
  end
end
