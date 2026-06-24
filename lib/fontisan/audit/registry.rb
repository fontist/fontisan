# frozen_string_literal: true

module Fontisan
  module Audit
    # Ordered list of extractor classes run for every audit face.
    #
    # Order matters only for human-readable output (text formatter).
    # All extractors are independent; their outputs are merged into
    # one big hash before constructing the AuditReport.
    #
    # Add new extractors here. AuditCommand never enumerates them
    # directly (OCP: adding a concern = one line here + one file).
    module Registry
      # Full audit: every concern.
      ORDERED_EXTRACTORS = [
        Extractors::Provenance,
        Extractors::Identity,
        Extractors::Style,
        Extractors::Licensing,
        Extractors::Metrics,
        Extractors::Hinting,
        Extractors::ColorCapabilities,
        Extractors::VariationDetail,
        Extractors::OpenTypeLayout,
        Extractors::Coverage,
        Extractors::Aggregations,
        Extractors::LanguageCoverage,
      ].freeze

      # Brief audit: only the cheap, name-table-only extractors. Skips
      # metrics/hinting/color/variation/layout (extra table loads) and
      # aggregations/language coverage (need UCD/CLDR indices). Used by
      # `fontisan audit --brief` for a fast inventory pass.
      BRIEF_EXTRACTORS = [
        Extractors::Provenance,
        Extractors::Identity,
        Extractors::Style,
        Extractors::Licensing,
        Extractors::Coverage,
      ].freeze

      # Iterate the extractors appropriate for the given mode.
      #
      # @param mode [Symbol] :full (default) or :brief
      # @yieldparam extractor_class [Class]
      def self.each(mode: :full, &)
        extractors_for(mode).each(&)
      end

      # @param mode [Symbol] :full or :brief
      # @return [Array<Class>] the extractor list for the given mode
      def self.extractors_for(mode)
        case mode
        when :brief then BRIEF_EXTRACTORS
        else ORDERED_EXTRACTORS
        end
      end
    end
  end
end
