# frozen_string_literal: true

# Namespace hub for audit-related models.
#
# All Models::Audit::* constants are autoloaded from here.

module Fontisan
  module Models
    module Audit
      autoload :AuditBlock,  "fontisan/models/audit/audit_block"
      autoload :AuditAxis,   "fontisan/models/audit/audit_axis"
      autoload :AuditReport, "fontisan/models/audit/audit_report"
      autoload :ColorCapabilities, "fontisan/models/audit/color_capabilities"
      autoload :EmbeddingType, "fontisan/models/audit/embedding_type"
      autoload :FsSelectionFlags, "fontisan/models/audit/fs_selection_flags"
      autoload :GaspRange, "fontisan/models/audit/gasp_range"
      autoload :Hinting, "fontisan/models/audit/hinting"
      autoload :Licensing, "fontisan/models/audit/licensing"
      autoload :Metrics, "fontisan/models/audit/metrics"
    end
  end
end
