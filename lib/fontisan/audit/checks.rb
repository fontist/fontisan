# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Audit
    # Individual audit check implementations. Each is a standalone class
    # under {Audit::Check} that implements `.call(font)` and `.code`.
    #
    # Adding a new check = one file + one autoload entry here. No edits
    # to {CheckRegistry} or {AuditCommand} required (Open/Closed).
    module Checks
      autoload :TableDirectoryCheck, "fontisan/audit/checks/table_directory_check"
      autoload :GlyphNameCheck, "fontisan/audit/checks/glyph_name_check"
      autoload :CmapCheck, "fontisan/audit/checks/cmap_check"
      autoload :OtsCompatibilityCheck,
               "fontisan/audit/checks/ots_compatibility_check"
      autoload :CollectionIntegrityCheck,
               "fontisan/audit/checks/collection_integrity_check"
    end
  end
end
