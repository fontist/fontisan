# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Model for glyph information
    class GlyphInfo < Lutaml::Model::Serializable
      attribute :glyph_count, :integer
      attribute :glyph_names, :string, collection: true
      attribute :source, :string

      json do
        map "glyph_count", to: :glyph_count
        map "glyph_names", to: :glyph_names
        map "source", to: :source
      end

      yaml do
        map "glyph_count", to: :glyph_count
        map "glyph_names", to: :glyph_names
        map "source", to: :source
      end
    end
  end
end
