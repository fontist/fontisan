# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Loca strategy: emit one entry per subset glyph + a final offset,
      # using short or long format based on the source head.index_to_loc_format.
      # Glyph offsets come from [SharedState], populated earlier by the
      # Glyf strategy. If Glyf hasn't run yet (e.g. direct invocation
      # from a spec), this strategy triggers the build lazily.
      class Loca
        # @param context [SubsetContext]
        # @param tag [String] "loca"
        # @param table [Loca] parsed loca table (unused)
        # @return [String] binary loca bytes for the subset
        def self.call(context:, tag:, table:)
          offsets = context.state.loca_offsets
          if offsets.nil?
            builder = GlyfLocaBuilder.new(font: context.font,
                                          mapping: context.mapping).build
            context.state.glyf_data = builder.glyf_data
            context.state.loca_offsets = builder.loca_offsets
            context.state.subset_bbox = builder.bbox
            offsets = builder.loca_offsets
          end

          head = context.font.table("head")
          data = String.new(encoding: Encoding::BINARY)

          if head.index_to_loc_format.zero?
            offsets.each { |o| data << [o / 2].pack("n") }
          else
            offsets.each { |o| data << [o].pack("N") }
          end

          data
        end
      end
    end
  end
end
