# frozen_string_literal: true

# Autoload hub for the Fontisan::Audit namespace.
#
# AuditCommand (under Commands::AuditCommand) builds a Context and
# runs every extractor in Audit::Registry, merging their outputs
# into a single AuditReport.

module Fontisan
  module Audit
    autoload :Context, "fontisan/audit/context"
    autoload :CodepointRangeCoalescer, "fontisan/audit/codepoint_range_coalescer"
    autoload :Differ, "fontisan/audit/differ"
    autoload :Registry, "fontisan/audit/registry"
    autoload :Extractors, "fontisan/audit/extractors"
    autoload :StyleExtractor, "fontisan/audit/style_extractor"
  end
end
