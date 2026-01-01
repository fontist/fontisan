# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Bitmap strike representation model
    #
    # Represents a bitmap strike (size) from the CBLC table. Each strike contains
    # bitmap glyphs at a specific ppem (pixels per em) size.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating a bitmap strike
    #   strike = BitmapStrike.new
    #   strike.ppem = 16
    #   strike.start_glyph_id = 10
    #   strike.end_glyph_id = 100
    #   strike.bit_depth = 32
    #
    # @example Serializing to JSON
    #   json = strike.to_json
    #   # {
    #   #   "ppem": 16,
    #   #   "start_glyph_id": 10,
    #   #   "end_glyph_id": 100,
    #   #   "bit_depth": 32
    #   # }
    class BitmapStrike < Lutaml::Model::Serializable
      # @!attribute ppem
      #   @return [Integer] Pixels per em (square pixels)
      attribute :ppem, :integer

      # @!attribute start_glyph_id
      #   @return [Integer] First glyph ID in this strike
      attribute :start_glyph_id, :integer

      # @!attribute end_glyph_id
      #   @return [Integer] Last glyph ID in this strike
      attribute :end_glyph_id, :integer

      # @!attribute bit_depth
      #   @return [Integer] Bit depth (1, 2, 4, 8, or 32)
      attribute :bit_depth, :integer

      # @!attribute num_glyphs
      #   @return [Integer] Number of glyphs in this strike
      attribute :num_glyphs, :integer

      # Get glyph IDs covered by this strike
      #
      # @return [Range] Range of glyph IDs
      def glyph_range
        start_glyph_id..end_glyph_id
      end

      # Check if this strike covers a specific glyph ID
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph is in range
      def includes_glyph?(glyph_id)
        glyph_range.include?(glyph_id)
      end

      # Get the color depth description
      #
      # @return [String] Human-readable color depth
      def color_depth
        case bit_depth
        when 1 then "1-bit (monochrome)"
        when 2 then "2-bit (4 colors)"
        when 4 then "4-bit (16 colors)"
        when 8 then "8-bit (256 colors)"
        when 32 then "32-bit (full color with alpha)"
        else "#{bit_depth}-bit"
        end
      end

      # Check if this is a color strike (32-bit)
      #
      # @return [Boolean] True if 32-bit color
      def color?
        bit_depth == 32
      end

      # Check if this is a monochrome strike (1-bit)
      #
      # @return [Boolean] True if 1-bit monochrome
      def monochrome?
        bit_depth == 1
      end
    end
  end
end