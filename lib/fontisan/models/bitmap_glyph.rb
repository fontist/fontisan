# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Bitmap glyph representation model
    #
    # Represents a bitmap glyph from the CBDT/CBLC tables. Each glyph contains
    # bitmap image data at a specific ppem size.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating a bitmap glyph
    #   glyph = BitmapGlyph.new
    #   glyph.glyph_id = 42
    #   glyph.ppem = 16
    #   glyph.format = "PNG"
    #   glyph.width = 16
    #   glyph.height = 16
    #   glyph.data_size = 256
    #
    # @example Serializing to JSON
    #   json = glyph.to_json
    #   # {
    #   #   "glyph_id": 42,
    #   #   "ppem": 16,
    #   #   "format": "PNG",
    #   #   "width": 16,
    #   #   "height": 16,
    #   #   "data_size": 256
    #   # }
    class BitmapGlyph < Lutaml::Model::Serializable
      # @!attribute glyph_id
      #   @return [Integer] Glyph ID
      attribute :glyph_id, :integer

      # @!attribute ppem
      #   @return [Integer] Pixels per em for this bitmap
      attribute :ppem, :integer

      # @!attribute format
      #   @return [String] Bitmap format (e.g., "PNG", "JPEG", "TIFF")
      attribute :format, :string

      # @!attribute width
      #   @return [Integer] Bitmap width in pixels
      attribute :width, :integer

      # @!attribute height
      #   @return [Integer] Bitmap height in pixels
      attribute :height, :integer

      # @!attribute bit_depth
      #   @return [Integer] Bit depth (1, 2, 4, 8, 32)
      attribute :bit_depth, :integer

      # @!attribute data_size
      #   @return [Integer] Size of bitmap data in bytes
      attribute :data_size, :integer

      # @!attribute data_offset
      #   @return [Integer] Offset to bitmap data in CBDT table
      attribute :data_offset, :integer

      # Check if this is a PNG bitmap
      #
      # @return [Boolean] True if format is PNG
      def png?
        format&.upcase == "PNG"
      end

      # Check if this is a JPEG bitmap
      #
      # @return [Boolean] True if format is JPEG
      def jpeg?
        format&.upcase == "JPEG"
      end

      # Check if this is a TIFF bitmap
      #
      # @return [Boolean] True if format is TIFF
      def tiff?
        format&.upcase == "TIFF"
      end

      # Check if this is a color bitmap (32-bit)
      #
      # @return [Boolean] True if 32-bit color
      def color?
        bit_depth == 32
      end

      # Check if this is a monochrome bitmap (1-bit)
      #
      # @return [Boolean] True if 1-bit monochrome
      def monochrome?
        bit_depth == 1
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

      # Get bitmap dimensions as string
      #
      # @return [String] Dimensions in "WxH" format
      def dimensions
        "#{width}x#{height}"
      end
    end
  end
end
