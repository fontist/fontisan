# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # NameRecord represents a single name record in the name table
        class NameRecord < Lutaml::Model::Serializable
          attribute :name_id, :integer
          attribute :platform_id, :integer
          attribute :plat_enc_id, :integer
          attribute :lang_id, :string
          attribute :string, :string

          xml do
            root "namerecord"

            map_attribute "nameID", to: :name_id
            map_attribute "platformID", to: :platform_id
            map_attribute "platEncID", to: :plat_enc_id
            map_attribute "langID", to: :lang_id

            map_content to: :string
          end
        end

        # NameTable represents the 'name' table in TTX format
        #
        # Contains human-readable information about the font following
        # the OpenType specification for the name table.
        class NameTable < Lutaml::Model::Serializable
          attribute :name_records, NameRecord, collection: true

          xml do
            root "name"

            map_element "namerecord", to: :name_records
          end
        end
      end
    end
  end
end
