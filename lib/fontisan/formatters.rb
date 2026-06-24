# frozen_string_literal: true

# Autoload hub for the Fontisan::Formatters namespace.

module Fontisan
  module Formatters
    autoload :AuditDiffTextRenderer, "fontisan/formatters/audit_diff_text_renderer"
    autoload :AuditTextRenderer, "fontisan/formatters/audit_text_renderer"
    autoload :LibrarySummaryTextRenderer, "fontisan/formatters/library_summary_text_renderer"
    autoload :TextFormatter, "fontisan/formatters/text_formatter"
  end
end
