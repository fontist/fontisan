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
      autoload :EmbeddingType, "fontisan/models/audit/embedding_type"
      autoload :FsSelectionFlags, "fontisan/models/audit/fs_selection_flags"
      autoload :Licensing, "fontisan/models/audit/licensing"
    end
  end
end
