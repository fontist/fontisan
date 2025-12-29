# frozen_string_literal: true

require "lutaml/model"
require_relative "font_info"

module Fontisan
  module Models
    # Model for collection brief information
    #
    # Represents collection metadata plus brief info for each font.
    # Used by InfoCommand in brief mode for collections.
    #
    # @example Creating collection brief info
    #   info = CollectionBriefInfo.new(
    #     collection_path: "fonts.ttc",
    #     num_fonts: 3,
    #     fonts: [font_info1, font_info2, font_info3]
    #   )
    class CollectionBriefInfo < Lutaml::Model::Serializable
      attribute :collection_path, :string
      attribute :num_fonts, :integer
      attribute :fonts, FontInfo, collection: true

      key_value do
        map "collection_path", to: :collection_path
        map "num_fonts", to: :num_fonts
        map "fonts", to: :fonts
      end
    end
  end
end
