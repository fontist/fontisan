# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      # GlyphID entry in GlyphOrder
      class GlyphId < Lutaml::Model::Serializable
        attribute :id, :integer
        attribute :name, :string

        xml do
          root "GlyphID"
          map_attribute "id", to: :id
          map_attribute "name", to: :name
        end
      end

      # GlyphOrder section in TTX
      class GlyphOrder < Lutaml::Model::Serializable
        attribute :glyph_ids, GlyphId, collection: true

        xml do
          root "GlyphOrder"
          map_element "GlyphID", to: :glyph_ids
        end
      end
    end
  end
end
