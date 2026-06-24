# frozen_string_literal: true

# Autoload hub for the Fontisan::Commands namespace.

module Fontisan
  module Commands
    autoload :AuditCommand, "fontisan/commands/audit_command"
    autoload :BaseCommand, "fontisan/commands/base_command"
    autoload :ConvertCommand, "fontisan/commands/convert_command"
    autoload :DumpTableCommand, "fontisan/commands/dump_table_command"
    autoload :ExportCommand, "fontisan/commands/export_command"
    autoload :FeaturesCommand, "fontisan/commands/features_command"
    autoload :GlyphsCommand, "fontisan/commands/glyphs_command"
    autoload :InfoCommand, "fontisan/commands/info_command"
    autoload :InstanceCommand, "fontisan/commands/instance_command"
    autoload :LsCommand, "fontisan/commands/ls_command"
    autoload :OpticalSizeCommand, "fontisan/commands/optical_size_command"
    autoload :PackCommand, "fontisan/commands/pack_command"
    autoload :ScriptsCommand, "fontisan/commands/scripts_command"
    autoload :SubsetCommand, "fontisan/commands/subset_command"
    autoload :TablesCommand, "fontisan/commands/tables_command"
    autoload :UnicodeCommand, "fontisan/commands/unicode_command"
    autoload :UnpackCommand, "fontisan/commands/unpack_command"
    autoload :ValidateCommand, "fontisan/commands/validate_command"
    autoload :VariableCommand, "fontisan/commands/variable_command"
  end
end
