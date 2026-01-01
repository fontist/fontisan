# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # SVG glyph representation model
    #
    # Represents an SVG document for a glyph or range of glyphs from the SVG table.
    # Each SVG document can cover multiple glyph IDs and may be compressed.
    #
    # This model uses lutaml-model for structured serialization to YAML/JSON/XML.
    #
    # @example Creating an SVG glyph
    #   svg_glyph = SvgGlyph.new
    #   svg_glyph.glyph_id = 100
    #   svg_glyph.start_glyph_id = 100
    #   svg_glyph.end_glyph_id = 105
    #   svg_glyph.svg_content = '<svg>...</svg>'
    #   svg_glyph.compressed = false
    #
    # @example Serializing to JSON
    #   json = svg_glyph.to_json
    #   # {
    #   #   "glyph_id": 100,
    #   #   "start_glyph_id": 100,
    #   #   "end_glyph_id": 105,
    #   #   "svg_content": "<svg>...</svg>",
    #   #   "compressed": false
    #   # }
    class SvgGlyph < Lutaml::Model::Serializable
      # @!attribute glyph_id
      #   @return [Integer] Primary glyph ID (usually same as start_glyph_id)
      attribute :glyph_id, :integer

      # @!attribute start_glyph_id
      #   @return [Integer] First glyph ID in range covered by this SVG
      attribute :start_glyph_id, :integer

      # @!attribute end_glyph_id
      #   @return [Integer] Last glyph ID in range covered by this SVG
      attribute :end_glyph_id, :integer

      # @!attribute svg_content
      #   @return [String] SVG XML content (decompressed)
      attribute :svg_content, :string

      # @!attribute compressed
      #   @return [Boolean] Whether the original data was gzip compressed
      attribute :compressed, :boolean, default: -> { false }

      # Get glyph IDs covered by this SVG document
      #
      # @return [Range] Range of glyph IDs
      def glyph_range
        start_glyph_id..end_glyph_id
      end

      # Check if this SVG covers a specific glyph ID
      #
      # @param glyph_id [Integer] Glyph ID to check
      # @return [Boolean] True if glyph is in range
      def includes_glyph?(glyph_id)
        glyph_range.include?(glyph_id)
      end

      # Check if this SVG covers multiple glyphs
      #
      # @return [Boolean] True if range includes more than one glyph
      def covers_multiple_glyphs?
        start_glyph_id != end_glyph_id
      end

      # Get the number of glyphs covered by this SVG
      #
      # @return [Integer] Number of glyphs in range
      def num_glyphs
        end_glyph_id - start_glyph_id + 1
      end

      # Check if SVG content is present
      #
      # @return [Boolean] True if svg_content is not nil or empty
      def has_content?
        !svg_content.nil? && !svg_content.empty?
      end
    end
  end
end
