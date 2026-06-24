# frozen_string_literal: true

# Autoload hub for the Fontisan::Binary namespace.

module Fontisan
  module Binary
    autoload :BaseRecord, "fontisan/binary/base_record"
    autoload :OffsetTable, "fontisan/binary/structures"
    autoload :TableDirectoryEntry, "fontisan/binary/structures"
  end
end
