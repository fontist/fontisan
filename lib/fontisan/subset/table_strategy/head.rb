# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Head strategy: recompute xMin/yMin/xMax/yMax (offsets 36–43) from
      # the subset's actual glyphs. The source TTC's bbox covers every
      # donor font in the collection and is far larger than any per-block
      # subset needs; an inflated bbox makes browsers render glyphs at
      # the wrong visual size. The remaining head fields pass through
      # unchanged — checksumAdjustment is rewritten by FontWriter.
      class Head
        # @param context [SubsetContext]
        # @param tag [String] "head"
        # @param table [Head] parsed head table (unused)
        # @return [String] binary head bytes for the subset
        def self.call(context:, tag:, table:)
          ensure_glyf_built!(context)

          data = context.font.table_data["head"].dup
          bbox = context.state.subset_bbox
          return data unless bbox

          x_min, y_min, x_max, y_max = bbox
          data[36, 8] = [x_min, y_min, x_max, y_max].pack("n4")
          data
        end

        def self.ensure_glyf_built!(context)
          return if context.state.glyf_data
          return unless context.font.table_data["glyf"]

          builder = GlyfLocaBuilder.new(font: context.font,
                                        mapping: context.mapping).build
          context.state.glyf_data = builder.glyf_data
          context.state.loca_offsets = builder.loca_offsets
          context.state.subset_bbox = builder.bbox
        end
        private_class_method :ensure_glyf_built!
      end
    end
  end
end
