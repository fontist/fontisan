# frozen_string_literal: true

module Fontisan
  # Audit-layer validation axes. Each check is a standalone module that
  # produces structured issues when run against a loaded font. Checks
  # are MECE by design: one concern per check (checksums, glyph names,
  # cmap subtables, OTS compatibility, collection integrity, etc.).
  #
  # Checks are independent of the existing `Validators::*` framework
  # (which uses a DSL and produces boolean pass/fail per check). The
  # audit checks produce detailed `Models::ValidationReport::Issue`
  # records so the consumer knows exactly what failed and where.
  #
  # @see Models::ValidationReport::Issue
  module Audit
    autoload :Check, "fontisan/audit/check"
    autoload :CheckRegistry, "fontisan/audit/check_registry"
    autoload :Checks, "fontisan/audit/checks"
  end
end
