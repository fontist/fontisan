# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Post strategy: if the `drop_names` option is set, rewrite as a
      # version 3.0 post table (no glyph names). Otherwise pass through
      # the source post bytes.
      class Post
        # @param context [SubsetContext]
        # @param tag [String] "post"
        # @param table [Post] parsed post table
        # @return [String] binary post bytes for the subset
        def self.call(context:, tag:, table:)
          return build_v3(context) if context.options.drop_names

          context.font.table_data["post"]
        end

        def self.build_v3(context)
          data = String.new(encoding: Encoding::BINARY)
          data << [0x00030000].pack("N") # version 3.0

          original = context.font.table_data["post"]
          data << if original&.length && original.length >= 32
                    original[4, 28]
                  else
                    [0, 0, 0, 0, 0, 0, 0].pack("N7")
                  end

          data
        end
        private_class_method :build_v3
      end
    end
  end
end
