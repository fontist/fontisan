# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # FontInfo model represents comprehensive font metadata
    # extracted from various font tables (name, head, OS/2, etc.)
    #
    # This model provides a unified interface for accessing font information
    # and supports serialization to YAML and JSON formats through lutaml-model.
    class FontInfo < Lutaml::Model::Serializable
      attribute :font_format, :string
      attribute :is_variable, Lutaml::Model::Type::Boolean
      attribute :family_name, :string
      attribute :subfamily_name, :string
      attribute :full_name, :string
      attribute :postscript_name, :string
      attribute :postscript_cid_name, :string
      attribute :preferred_family, :string
      attribute :preferred_subfamily, :string
      attribute :mac_font_menu_name, :string
      attribute :version, :string
      attribute :unique_id, :string
      attribute :description, :string
      attribute :designer, :string
      attribute :designer_url, :string
      attribute :manufacturer, :string
      attribute :vendor_url, :string
      attribute :vendor_id, :string
      attribute :trademark, :string
      attribute :copyright, :string
      attribute :license_description, :string
      attribute :license_url, :string
      attribute :sample_text, :string
      attribute :font_revision, :float
      attribute :permissions, :string
      attribute :units_per_em, :integer
      attribute :collection_offset, :integer

      key_value do
        map "font_format", to: :font_format
        map "is_variable", to: :is_variable
        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "full_name", to: :full_name
        map "postscript_name", to: :postscript_name
        map "postscript_cid_name", to: :postscript_cid_name
        map "preferred_family", to: :preferred_family
        map "preferred_subfamily", to: :preferred_subfamily
        map "mac_font_menu_name", to: :mac_font_menu_name
        map "version", to: :version
        map "unique_id", to: :unique_id
        map "description", to: :description
        map "designer", to: :designer
        map "designer_url", to: :designer_url
        map "manufacturer", to: :manufacturer
        map "vendor_url", to: :vendor_url
        map "vendor_id", to: :vendor_id
        map "trademark", to: :trademark
        map "copyright", to: :copyright
        map "license_description", to: :license_description
        map "license_url", to: :license_url
        map "sample_text", to: :sample_text
        map "font_revision", to: :font_revision
        map "permissions", to: :permissions
        map "units_per_em", to: :units_per_em
        map "collection_offset", to: :collection_offset
      end
    end
  end
end
