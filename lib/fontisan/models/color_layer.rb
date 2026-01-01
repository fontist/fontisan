# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Color layer information model
    #
    # Represents a single color layer in a COLR glyph. Each layer specifies
    # a glyph ID to render and the palette index for its color.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating a color layer
    #   layer = ColorLayer.new
    #   layer.glyph_id = 42
    #   layer.palette_index = 2
    #   layer.color = "#FF0000FF"
    #
    # @example Serializing to YAML
    #   yaml = layer.to_yaml
    #   # glyph_id: 42
    #   # palette_index: 2
    #   # color: "#FF0000FF"
    class ColorLayer < Lutaml::Model::Serializable
      # @!attribute glyph_id
      #   @return [Integer] Glyph ID of the layer
      attribute :glyph_id, :integer

      # @!attribute palette_index
      #   @return [Integer] Index into CPAL palette (0xFFFF = foreground)
      attribute :palette_index, :integer

      # @!attribute color
      #   @return [String, nil] Hex color from palette (#RRGGBBAA), nil if foreground
      attribute :color, :string

      # Check if this layer uses the foreground color
      #
      # @return [Boolean] True if using text foreground color
      def uses_foreground_color?
        palette_index == 0xFFFF
      end

      # Check if this layer uses a palette color
      #
      # @return [Boolean] True if using CPAL palette color
      def uses_palette_color?
        !uses_foreground_color?
      end
    end
  end
end
