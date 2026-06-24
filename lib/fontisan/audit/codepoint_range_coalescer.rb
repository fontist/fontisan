# frozen_string_literal: true

module Fontisan
  module Audit
    # Coalesces a flat codepoint list into contiguous {Models::Audit::CodepointRange}s.
    #
    # Single static call site, deterministic output. Used by the Coverage
    # extractor to produce the compact range view that is the default
    # AuditReport shape.
    module CodepointRangeCoalescer
      module_function

      # @param codepoints [Enumerable<Integer>] any enumeration of integers
      # @return [Array<Models::Audit::CodepointRange>] contiguous, sorted
      def call(codepoints)
        return [] if codepoints.nil? || codepoints.empty?

        sorted = codepoints.sort.uniq
        ranges = []
        range_start = sorted[0]
        prev = sorted[0]

        sorted[1..].each do |cp|
          next if cp == prev # defensive: .uniq already handles this

          if cp == prev + 1
            prev = cp
          else
            ranges << Models::Audit::CodepointRange.new(first_cp: range_start,
                                                        last_cp: prev)
            range_start = cp
            prev = cp
          end
        end
        ranges << Models::Audit::CodepointRange.new(first_cp: range_start,
                                                    last_cp: prev)
        ranges
      end
    end
  end
end
