# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # CBDT strategy: delegate to [ColorBitmapSubsetter], which produces
      # both CBDT and CBLC bytes in a single pass. The Cblc strategy
      # reads from the same collaborator so the two tables stay
      # consistent.
      class Cbdt
        # @param context [SubsetContext]
        # @param tag [String] "CBDT"
        # @param table [Cbdt] parsed CBDT table (unused)
        # @return [String] subset CBDT bytes
        def self.call(context:, tag:, table:)
          color_bitmap_subsetter(context).cbdt_bytes
        end

        # @param context [SubsetContext]
        # @return [ColorBitmapSubsetter] cached on the shared state so the
        #   Cblc strategy reuses the same pass
        def self.color_bitmap_subsetter(context)
          context.state.color_bitmap_subsetter ||= ColorBitmapSubsetter.new(font: context.font,
                                                                            mapping: context.mapping).build
        end
        private_class_method :color_bitmap_subsetter
      end
    end
  end
end
