# frozen_string_literal: true

# Autoload hub for the Fontisan::Audit::Extractors namespace.
#
# Each extractor is a small MECE class with a single `#extract(context)`
# method returning a hash of AuditReport fields. The Audit::Registry
# declares the ordered list.

module Fontisan
  module Audit
    module Extractors
      autoload :Base, "fontisan/audit/extractors/base"
      autoload :Provenance, "fontisan/audit/extractors/provenance"
      autoload :Identity, "fontisan/audit/extractors/identity"
      autoload :Style, "fontisan/audit/extractors/style"
      autoload :Licensing, "fontisan/audit/extractors/licensing"
      autoload :Metrics, "fontisan/audit/extractors/metrics"
      autoload :Hinting, "fontisan/audit/extractors/hinting"
      autoload :ColorCapabilities, "fontisan/audit/extractors/color_capabilities"
      autoload :VariationDetail, "fontisan/audit/extractors/variation_detail"
      autoload :Coverage, "fontisan/audit/extractors/coverage"
      autoload :Aggregations, "fontisan/audit/extractors/aggregations"
    end
  end
end
