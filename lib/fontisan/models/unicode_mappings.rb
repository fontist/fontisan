# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Model for a single Unicode to glyph mapping
    class UnicodeMapping < Lutaml::Model::Serializable
      attribute :codepoint, :string
      attribute :glyph_index, :integer
      attribute :glyph_name, :string

      json do
        map "codepoint", to: :codepoint
        map "glyph_index", to: :glyph_index
        map "glyph_name", to: :glyph_name
      end

      yaml do
        map "codepoint", to: :codepoint
        map "glyph_index", to: :glyph_index
        map "glyph_name", to: :glyph_name
      end
    end

    # Model for collection of Unicode mappings
    class UnicodeMappings < Lutaml::Model::Serializable
      attribute :count, :integer
      attribute :mappings, UnicodeMapping, collection: true

      json do
        map "count", to: :count
        map "mappings", to: :mappings
      end

      yaml do
        map "count", to: :count
        map "mappings", to: :mappings
      end
    end
  end
end
