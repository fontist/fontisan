# frozen_string_literal: true

require "lutaml/model"
require_relative "collection_font_summary"

module Fontisan
  module Models
    # Model for collection font listing
    #
    # Represents a list of fonts within a TTC/OTC collection.
    # Used by LsCommand when operating on collection files.
    #
    # @example Creating a collection list
    #   list = CollectionListInfo.new(
    #     collection_path: "fonts.ttc",
    #     num_fonts: 6,
    #     fonts: [summary1, summary2, ...]
    #   )
    class CollectionListInfo < Lutaml::Model::Serializable
      attribute :collection_path, :string
      attribute :num_fonts, :integer
      attribute :fonts, CollectionFontSummary, collection: true

      yaml do
        map "collection_path", to: :collection_path
        map "num_fonts", to: :num_fonts
        map "fonts", to: :fonts
      end

      json do
        map "collection_path", to: :collection_path
        map "num_fonts", to: :num_fonts
        map "fonts", to: :fonts
      end
    end
  end
end
