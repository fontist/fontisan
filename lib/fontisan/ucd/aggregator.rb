# frozen_string_literal: true

module Fontisan
  module Ucd
    # Produces audit-ready aggregations from a codepoint list + UCD indices.
    #
    # Pure: no I/O, no side effects. Caller passes the codepoints and the
    # blocks/scripts indices; Aggregator returns the aggregated summaries.
    module Aggregator
      module_function

      # Aggregate codepoints per Unicode block.
      #
      # Returns one hash per overlapping block, sorted by first_cp:
      #
      #   { name:, first_cp:, last_cp:, total:, covered:, fill_ratio:, complete: }
      #
      # @param codepoints [Array<Integer>] sorted not required
      # @param blocks_index [Index]
      # @return [Array<Hash>]
      def aggregate_blocks(codepoints, blocks_index)
        sorted = codepoints.sort
        return [] if sorted.empty?

        coverage = Hash.new { |h, k| h[k] = 0 }
        coverage.compare_by_identity
        first_cp = sorted.first
        last_cp = sorted.last

        overlapping = blocks_index.each_overlapping(first_cp, last_cp).to_a
        overlapping.each do |entry|
          coverage[entry] = count_in_range(sorted, [entry.first_cp, entry.last_cp])
        end

        overlapping.map do |entry|
          covered = coverage[entry]
          total = entry.size
          {
            name: entry.name,
            first_cp: entry.first_cp,
            last_cp: entry.last_cp,
            total: total,
            covered: covered,
            fill_ratio: covered.fdiv(total).round(4),
            complete: covered == total,
          }
        end
      end

      # Aggregate unique script names from codepoints.
      #
      # @param codepoints [Array<Integer>]
      # @param scripts_index [Index]
      # @return [Array<String>] sorted unique script names
      def aggregate_scripts(codepoints, scripts_index)
        scripts = codepoints.filter_map { |cp| scripts_index.lookup(cp) }
        scripts.uniq.sort
      end

      # Count codepoints in `sorted` that fall within [first, last].
      # `sorted` must be sorted ascending.
      def count_in_range(sorted, range)
        first, last = range
        left = sorted.bsearch_index { |cp| cp >= first } || sorted.size
        return 0 if left == sorted.size

        right = sorted.bsearch_index { |cp| cp > last } || sorted.size
        right - left
      end
      private_class_method :count_in_range
    end
  end
end
