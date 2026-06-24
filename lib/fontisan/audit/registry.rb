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
      ORDERED_EXTRACTORS = [
        Extractors::Provenance,
        Extractors::Identity,
        Extractors::Style,
        Extractors::Licensing,
        Extractors::Metrics,
        Extractors::Coverage,
        Extractors::Aggregations,
      ].freeze

      def self.each(&)
        ORDERED_EXTRACTORS.each(&)
      end
    end
  end
end
