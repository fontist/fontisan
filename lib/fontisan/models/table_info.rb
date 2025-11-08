# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # TableEntry represents a single table directory entry in a font file
    #
    # Each entry contains metadata about a font table including its tag,
    # length, offset within the file, and checksum for validation.
    class TableEntry < Lutaml::Model::Serializable
      attribute :tag, :string
      attribute :length, :integer
      attribute :offset, :integer
      attribute :checksum, :integer

      json do
        map "tag", to: :tag
        map "length", to: :length
        map "offset", to: :offset
        map "checksum", to: :checksum
      end

      yaml do
        map "tag", to: :tag
        map "length", to: :length
        map "offset", to: :offset
        map "checksum", to: :checksum
      end
    end

    # TableInfo represents the table directory information from a font file
    #
    # This model contains the SFNT version identifier, the number of tables,
    # and a collection of TableEntry objects representing each table in the font.
    # It supports serialization to YAML and JSON formats through lutaml-model.
    class TableInfo < Lutaml::Model::Serializable
      attribute :sfnt_version, :string
      attribute :num_tables, :integer
      attribute :tables, TableEntry, collection: true

      json do
        map "sfnt_version", to: :sfnt_version
        map "num_tables", to: :num_tables
        map "tables", to: :tables
      end

      yaml do
        map "sfnt_version", to: :sfnt_version
        map "num_tables", to: :num_tables
        map "tables", to: :tables
      end
    end
  end
end
