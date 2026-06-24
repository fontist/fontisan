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
    end
  end
end
