# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Model for individual font summary within a collection
    #
    # Represents basic metadata for a single font in a TTC/OTC collection.
    # Used by CollectionListInfo to provide per-font summaries.
    #
    # @example Creating a font summary
    #   summary = CollectionFontSummary.new(
    #     index: 0,
    #     family_name: "Helvetica",
    #     subfamily_name: "Regular",
    #     postscript_name: "Helvetica-Regular",
    #     font_format: "TrueType",
    #     num_glyphs: 268,
    #     num_tables: 14
    #   )
    class CollectionFontSummary < Lutaml::Model::Serializable
      attribute :index, :integer
      attribute :family_name, :string
      attribute :subfamily_name, :string
      attribute :postscript_name, :string
      attribute :font_format, :string
      attribute :num_glyphs, :integer
      attribute :num_tables, :integer

      yaml do
        map "index", to: :index
        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "postscript_name", to: :postscript_name
        map "font_format", to: :font_format
        map "num_glyphs", to: :num_glyphs
        map "num_tables", to: :num_tables
      end

      json do
        map "index", to: :index
        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "postscript_name", to: :postscript_name
        map "font_format", to: :font_format
        map "num_glyphs", to: :num_glyphs
        map "num_tables", to: :num_tables
      end
    end
  end
end
