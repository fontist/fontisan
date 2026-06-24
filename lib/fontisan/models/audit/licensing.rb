# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Licensing + embedding + vendor provenance fields for a face.
      #
      # Combines the human-readable legal/identity fields from the name
      # table with the machine-readable embedding permissions from OS/2.
      # Type 1 fonts have no OS/2 — callers must tolerate a nil
      # embedding_type / fs_selection_flags / vendor_id.
      class Licensing < Lutaml::Model::Serializable
        # Name-table fields (English name IDs)
        attribute :copyright,          :string
        attribute :trademark,          :string
        attribute :manufacturer,       :string
        attribute :designer,           :string
        attribute :description,        :string
        attribute :vendor_url,         :string
        attribute :designer_url,       :string
        attribute :license_description, :string
        attribute :license_url, :string

        # OS/2 fields
        attribute :vendor_id,           :string
        attribute :embedding_type,      :string
        attribute :fs_selection_flags,  :string, collection: true

        key_value do
          map "copyright",           to: :copyright
          map "trademark",           to: :trademark
          map "manufacturer",        to: :manufacturer
          map "designer",            to: :designer
          map "description",         to: :description
          map "vendor_url",          to: :vendor_url
          map "designer_url",        to: :designer_url
          map "license_description", to: :license_description
          map "license_url",         to: :license_url
          map "vendor_id",           to: :vendor_id
          map "embedding_type",      to: :embedding_type
          map "fs_selection_flags",  to: :fs_selection_flags
        end
      end
    end
  end
end
