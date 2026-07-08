# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # CBLC strategy: delegate to [ColorBitmapSubsetter] (the same
      # collaborator used by the Cbdt strategy) so both tables stay
      # consistent. The subsetter is built lazily on first access and
      # cached on [SharedState].
      class Cblc
        # @param context [SubsetContext]
        # @param tag [String] "CBLC"
        # @param table [Cblc] parsed CBLC table (unused)
        # @return [String] subset CBLC bytes
        def self.call(context:, tag:, table:)
          color_bitmap_subsetter(context).cblc_bytes
        end

        def self.color_bitmap_subsetter(context)
          context.state.color_bitmap_subsetter ||= ColorBitmapSubsetter.new(font: context.font,
                                                                            mapping: context.mapping).build
        end
        private_class_method :color_bitmap_subsetter
      end
    end
  end
end
