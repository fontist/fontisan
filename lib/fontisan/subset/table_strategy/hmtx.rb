# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Hmtx strategy: emit one LongHorMetric per glyph in the subset's
      # glyph mapping, in the same order as the mapping. Also records
      # the maximum advanceWidth into [SharedState] so Hhea (which is
      # processed alphabetically before Hmtx) can read it.
      #
      # Tables are processed in profile order — Hhea comes before Hmtx
      # alphabetically — so Hhea reads its max advance via a private
      # helper that walks the source hmtx directly. Hmtx then stashes
      # the value into SharedState for any later consumer.
      class Hmtx
        # @param context [SubsetContext]
        # @param tag [String] "hmtx"
        # @param table [Hmtx] parsed hmtx table
        # @return [String] binary hmtx bytes for the subset
        def self.call(context:, tag:, table:)
          ensure_parsed!(context, table)

          data = String.new(encoding: Encoding::BINARY)
          max_advance = 0

          context.mapping.old_ids.each do |old_id|
            metric = table.metric_for(old_id)
            next unless metric

            advance = metric[:advance_width]
            max_advance = advance if advance && advance > max_advance
            data << [advance].pack("n")
            data << [metric[:lsb]].pack("n")
          end

          context.state.subset_max_advance = max_advance
          data
        end

        def self.ensure_parsed!(context, table)
          return if table.parsed?

          hhea = context.font.table("hhea")
          maxp = context.font.table("maxp")
          table.parse_with_context(hhea.number_of_h_metrics,
                                   maxp.num_glyphs)
        end
        private_class_method :ensure_parsed!
      end
    end
  end
end
