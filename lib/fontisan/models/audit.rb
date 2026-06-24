# frozen_string_literal: true

# Namespace hub for audit-related models.
#
# All Models::Audit::* constants are autoloaded from here.

module Fontisan
  module Models
    module Audit
      autoload :AuditBlock,  "fontisan/models/audit/audit_block"
      autoload :AuditAxis,   "fontisan/models/audit/audit_axis"
      autoload :AuditDiff,   "fontisan/models/audit/audit_diff"
      autoload :AuditReport, "fontisan/models/audit/audit_report"
      autoload :CodepointRange, "fontisan/models/audit/codepoint_range"
      autoload :CodepointSetDiff, "fontisan/models/audit/codepoint_set_diff"
      autoload :ColorCapabilities, "fontisan/models/audit/color_capabilities"
      autoload :DuplicateGroup, "fontisan/models/audit/duplicate_group"
      autoload :EmbeddingType, "fontisan/models/audit/embedding_type"
      autoload :FieldChange, "fontisan/models/audit/field_change"
      autoload :FsSelectionFlags, "fontisan/models/audit/fs_selection_flags"
      autoload :GaspRange, "fontisan/models/audit/gasp_range"
      autoload :Hinting, "fontisan/models/audit/hinting"
      autoload :LibrarySummary, "fontisan/models/audit/library_summary"
      autoload :Licensing, "fontisan/models/audit/licensing"
      autoload :Metrics, "fontisan/models/audit/metrics"
      autoload :NamedInstance, "fontisan/models/audit/named_instance"
      autoload :OpenTypeLayout, "fontisan/models/audit/opentype_layout"
      autoload :ScriptCoverageRow, "fontisan/models/audit/script_coverage_row"
      autoload :ScriptFeatures, "fontisan/models/audit/script_features"
      autoload :VariationDetail, "fontisan/models/audit/variation_detail"
    end
  end
end
