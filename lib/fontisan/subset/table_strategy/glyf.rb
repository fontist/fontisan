# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Glyf strategy: extract each subset glyph's bytes from the source
      # glyf table (remapping composite component glyph IDs), build the
      # corresponding loca offsets, and stash both into [SharedState] so
      # the Loca strategy can read them. Also records the union bbox
      # for the Head strategy.
      class Glyf
        # @param context [SubsetContext]
        # @param tag [String] "glyf"
        # @param table [Glyf] parsed glyf table (unused; builder reads
        #   the table from `context.font` directly so it sees the same
        #   instance)
        # @return [String] binary glyf bytes for the subset
        def self.call(context:, tag:, table:)
          builder = GlyfLocaBuilder.new(font: context.font,
                                        mapping: context.mapping).build
          context.state.glyf_data = builder.glyf_data
          context.state.loca_offsets = builder.loca_offsets
          context.state.subset_bbox = builder.bbox
          builder.glyf_data
        end
      end
    end
  end
end
