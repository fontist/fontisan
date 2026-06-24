# frozen_string_literal: true

# Namespace hub for Audit::* support classes.
#
# AuditCommand itself lives under Commands::AuditCommand.

module Fontisan
  module Audit
    autoload :StyleExtractor, "fontisan/audit/style_extractor"
  end
end
