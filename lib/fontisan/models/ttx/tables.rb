# frozen_string_literal: true

# Autoload hub for the Fontisan::Models::Ttx::Tables namespace.

module Fontisan
  module Models
    module Ttx
      module Tables
        autoload :BinaryTable, "fontisan/models/ttx/tables/binary_table"
        autoload :HeadTable, "fontisan/models/ttx/tables/head_table"
        autoload :HheaTable, "fontisan/models/ttx/tables/hhea_table"
        autoload :MaxpTable, "fontisan/models/ttx/tables/maxp_table"
        autoload :NameRecord, "fontisan/models/ttx/tables/name_table"
        autoload :NameTable, "fontisan/models/ttx/tables/name_table"
        autoload :Os2Table, "fontisan/models/ttx/tables/os2_table"
        autoload :Panose, "fontisan/models/ttx/tables/os2_table"
        autoload :PostTable, "fontisan/models/ttx/tables/post_table"
      end
    end
  end
end
