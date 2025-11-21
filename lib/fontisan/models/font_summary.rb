# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Model for quick font summary
    #
    # Represents a brief overview of an individual font file.
    # Used by LsCommand when operating on TTF/OTF files.
    #
    # @example Creating a font summary
    #   summary = FontSummary.new(
    #     font_path: "font.ttf",
    #     family_name: "Helvetica",
    #     subfamily_name: "Regular",
    #     font_format: "TrueType",
    #     num_glyphs: 268,
    #     num_tables: 14
    #   )
    class FontSummary < Lutaml::Model::Serializable
      attribute :font_path, :string
      attribute :family_name, :string
      attribute :subfamily_name, :string
      attribute :font_format, :string
      attribute :num_glyphs, :integer
      attribute :num_tables, :integer

      yaml do
        map "font_path", to: :font_path
        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "font_format", to: :font_format
        map "num_glyphs", to: :num_glyphs
        map "num_tables", to: :num_tables
      end

      json do
        map "font_path", to: :font_path
        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "font_format", to: :font_format
        map "num_glyphs", to: :num_glyphs
        map "num_tables", to: :num_tables
      end
    end
  end
end
