# frozen_string_literal: true

module Fontisan
  module Cldr
    # Produces audit-ready per-language coverage from a codepoint list
    # and a Cldr::Index of per-language exemplar sets.
    #
    # Pure: no I/O, no side effects.
    module Aggregator
      module_function

      # @param codepoints [Enumerable<Integer>] font's codepoints
      # @param languages_index [Cldr::Index]
      # @return [Array<Models::Cldr::LanguageCoverage>] sorted by
      #   descending coverage_ratio, then by language name
      def aggregate(codepoints, languages_index)
        font_set = Set.new(codepoints)

        languages_index.entries.map do |lang, required_set|
          covered = (font_set & required_set).size
          total = required_set.size
          Models::Cldr::LanguageCoverage.new(
            language: lang,
            covered: covered,
            total: total,
            coverage_ratio: total.zero? ? 0.0 : covered.fdiv(total).round(4),
            fully_supported: total.positive? && covered == total,
          )
        end.sort_by { |lc| [lc.coverage_ratio * -1, lc.language] }
      end
    end
  end
end
