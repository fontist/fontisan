# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Color palette information model
    #
    # Represents a color palette from the CPAL table. Each palette contains
    # an array of RGBA colors in hex format that can be referenced by
    # COLR layer palette indices.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating a color palette
    #   palette = ColorPalette.new
    #   palette.index = 0
    #   palette.num_colors = 3
    #   palette.colors = ["#FF0000FF", "#00FF00FF", "#0000FFFF"]
    #
    # @example Serializing to YAML
    #   yaml = palette.to_yaml
    #   # index: 0
    #   # num_colors: 3
    #   # colors:
    #   #   - "#FF0000FF"
    #   #   - "#00FF00FF"
    #   #   - "#0000FFFF"
    class ColorPalette < Lutaml::Model::Serializable
      # @!attribute index
      #   @return [Integer] Palette index (0-based)
      attribute :index, :integer

      # @!attribute num_colors
      #   @return [Integer] Number of colors in this palette
      attribute :num_colors, :integer

      # @!attribute colors
      #   @return [Array<String>] Array of hex color strings (#RRGGBBAA)
      attribute :colors, :string, collection: true

      # Get a color by index
      #
      # @param color_index [Integer] Color index within palette
      # @return [String, nil] Hex color string or nil if invalid index
      def color_at(color_index)
        return nil if color_index.negative? || color_index >= colors.length

        colors[color_index]
      end

      # Check if palette is empty
      #
      # @return [Boolean] True if no colors
      def empty?
        colors.nil? || colors.empty?
      end
    end
  end
end
