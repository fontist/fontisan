# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # OS/2 strategy: OS/2 currently passes through unchanged. Unicode
      # range pruning is left as future work — the source OS/2 ranges
      # remain valid (they describe the source character coverage, which
      # is a superset of the subset's).
      class Os2
        # @param context [SubsetContext]
        # @param tag [String] "OS/2"
        # @param table [Os2] parsed OS/2 table (unused)
        # @return [String] source OS/2 bytes verbatim
        def self.call(context:, tag:, table:)
          context.font.table_data[tag]
        end
      end
    end
  end
end
