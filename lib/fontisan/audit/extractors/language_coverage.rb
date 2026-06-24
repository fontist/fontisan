# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Per-language CLDR coverage for one face.
      #
      # Returned fields:
      #   language_coverage, cldr_version
      #
      # Opt-in only — `--with-language-coverage`. When off, Context#cldr
      # returns nil and this extractor emits an empty array + nil version.
      # MECE: this extractor is CLDR-driven; UCD block/script coverage
      # lives in {Extractors::Aggregations}.
      class LanguageCoverage < Base
        def extract(context)
          cldr = context.cldr
          return empty(nil) if cldr.nil?

          return empty(cldr[:version]) if cldr[:index].nil?

          {
            language_coverage: Cldr::Aggregator.aggregate(context.codepoints,
                                                          cldr[:index]),
            cldr_version: cldr[:version],
          }
        end

        private

        def empty(version)
          { language_coverage: [], cldr_version: version }
        end
      end
    end
  end
end
