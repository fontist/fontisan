# frozen_string_literal: true

require "lutaml/model"
require_relative "color_layer"

module Fontisan
  module Models
    # Color glyph information model
    #
    # Represents a complete color glyph from the COLR table, containing
    # multiple layers that are rendered in order to create the final
    # multi-colored glyph.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating a color glyph
    #   glyph = ColorGlyph.new
    #   glyph.glyph_id = 100
    #   glyph.num_layers = 3
    #   glyph.layers = [layer1, layer2, layer3]
    #
    # @example Serializing to JSON
    #   json = glyph.to_json
    #   # {
    #   #   "glyph_id": 100,
    #   #   "num_layers": 3,
    #   #   "layers": [...]
    #   # }
    class ColorGlyph < Lutaml::Model::Serializable
      # @!attribute glyph_id
      #   @return [Integer] Base glyph ID
      attribute :glyph_id, :integer

      # @!attribute num_layers
      #   @return [Integer] Number of color layers
      attribute :num_layers, :integer

      # @!attribute layers
      #   @return [Array<ColorLayer>] Array of color layers
      attribute :layers, ColorLayer, collection: true

      # Check if glyph has color layers
      #
      # @return [Boolean] True if glyph has layers
      def has_layers?
        num_layers&.positive? || false
      end

      # Check if glyph is empty
      #
      # @return [Boolean] True if no layers
      def empty?
        !has_layers?
      end
    end
  end
end
