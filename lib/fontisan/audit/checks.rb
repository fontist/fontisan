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
      autoload :VariableFontCheck, "fontisan/audit/checks/variable_font_check"
      autoload :HintingCheck, "fontisan/audit/checks/hinting_check"
      autoload :Woff2ValidationCheck,
               "fontisan/audit/checks/woff2_validation_check"
      autoload :FormatRoundTripCheck,
               "fontisan/audit/checks/format_round_trip_check"
      autoload :OpenTypeConformanceCheck,
               "fontisan/audit/checks/opentype_conformance_check"
      autoload :HeadCheck, "fontisan/audit/checks/head_check"
      autoload :HheaCheck, "fontisan/audit/checks/hhea_check"
      autoload :MaxpCheck, "fontisan/audit/checks/maxp_check"
      autoload :Os2Check, "fontisan/audit/checks/os2_check"
      autoload :NameTableCheck, "fontisan/audit/checks/name_table_check"
      autoload :PostCheck, "fontisan/audit/checks/post_check"
      autoload :KernCheck, "fontisan/audit/checks/kern_check"
      autoload :CffTableCheck, "fontisan/audit/checks/cff_table_check"
      autoload :GlyfTableCheck, "fontisan/audit/checks/glyf_table_check"
      autoload :LayoutTableCheck, "fontisan/audit/checks/layout_table_check"
      autoload :NamingConsistencyCheck,
               "fontisan/audit/checks/naming_consistency_check"
    end
  end
end
