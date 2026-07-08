# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Default fallback for tags that have no dedicated strategy.
      # Returns the source table bytes verbatim — used for tables that
      # don't need any glyph-aware subsetting (e.g. name, OS/2).
      class PassThrough
        # @param context [SubsetContext]
        # @param tag [String] table tag
        # @param table [Object, nil] parsed table (unused)
        # @return [String, nil] source binary bytes for `tag`, or nil
        def self.call(context:, tag:, table:)
          context.font.table_data[tag]
        end
      end
    end
  end
end
