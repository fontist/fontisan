# frozen_string_literal: true

module Fontisan
  module Subset
    module TableStrategy
      # Hhea strategy: rewrite numberOfHMetrics (offset 34, uint16) and
      # advanceWidthMax (offset 10, uint16). The source TTC's
      # advanceWidthMax covers every donor font and can be far larger
      # than any per-block subset needs; recomputing from the subset's
      # actual hmtx keeps the value honest.
      #
      # Hhea runs alphabetically before Hmtx, so the Hmtx strategy's
      # SharedState cache hasn't been populated yet — we walk the source
      # hmtx directly to find the max.
      class Hhea
        # @param context [SubsetContext]
        # @param tag [String] "hhea"
        # @param table [Hhea] parsed hhea table
        # @return [String] binary hhea bytes for the subset
        def self.call(context:, tag:, table:)
          data = table.to_binary_s.dup

          new_num_h_metrics = calculate_number_of_h_metrics(context, table)
          data[34, 2] = [new_num_h_metrics].pack("n")

          new_max = compute_subset_max_advance(context)
          data[10, 2] = [new_max].pack("n") if new_max.positive?

          data
        end

        def self.calculate_number_of_h_metrics(context, _table)
          hmtx = context.font.table("hmtx")
          if hmtx&.parsed? && hmtx.h_metrics
            hmtx.h_metrics.size
          else
            context.mapping.size
          end
        end

        def self.compute_subset_max_advance(context)
          hmtx = context.font.table("hmtx")
          return 0 unless hmtx

          unless hmtx.parsed?
            hhea = context.font.table("hhea")
            maxp = context.font.table("maxp")
            hmtx.parse_with_context(hhea.number_of_h_metrics,
                                    maxp.num_glyphs)
          end

          max_advance = 0
          context.mapping.old_ids.each do |old_id|
            metric = hmtx.metric_for(old_id)
            next unless metric

            advance = metric[:advance_width]
            max_advance = advance if advance && advance > max_advance
          end
          max_advance
        end
        private_class_method :calculate_number_of_h_metrics,
                             :compute_subset_max_advance
      end
    end
  end
end
