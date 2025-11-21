# frozen_string_literal: true

require "lutaml/model"
require_relative "glyph_order"
require_relative "tables/head_table"
require_relative "tables/name_table"
require_relative "tables/maxp_table"
require_relative "tables/hhea_table"
require_relative "tables/os2_table"
require_relative "tables/post_table"
require_relative "tables/binary_table"

module Fontisan
  module Models
    module Ttx
      # Root TTFont element for TTX format
      #
      # Represents the complete TTX XML structure following fonttools format.
      # This is the main container for all font data in TTX format.
      class TtFont < Lutaml::Model::Serializable
        attribute :sfnt_version, :string
        attribute :ttlib_version, :string, default: -> { "4.0" }
        attribute :glyph_order, GlyphOrder
        attribute :head_table, Tables::HeadTable
        attribute :hhea_table, Tables::HheaTable
        attribute :maxp_table, Tables::MaxpTable
        attribute :name_table, Tables::NameTable
        attribute :os2_table, Tables::Os2Table
        attribute :post_table, Tables::PostTable
        attribute :binary_tables, Tables::BinaryTable, collection: true

        xml do
          root "ttFont"

          map_attribute "sfntVersion", to: :sfnt_version
          map_attribute "ttLibVersion", to: :ttlib_version

          map_element "GlyphOrder", to: :glyph_order
          map_element "head", to: :head_table
          map_element "hhea", to: :hhea_table
          map_element "maxp", to: :maxp_table
          map_element "name", to: :name_table
          map_element "OS_2", to: :os2_table
          map_element "post", to: :post_table
        end
      end
    end
  end
end
