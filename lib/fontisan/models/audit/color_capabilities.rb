# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Color-font capability summary for one face.
      #
      # Answers: is this a color font, and if so, which format(s)?
      # Modern color font formats are mutually exclusive in design but a
      # single face can carry more than one (e.g. NotoColorEmoji ships
      # COLR + CBDT + SVG so legacy and modern stacks all render).
      #
      # `color_formats` is derived at extraction time so consumers read a
      # flat string list instead of re-deriving from the boolean lattice.
      # Empty array ⇒ no color support.
      class ColorCapabilities < Lutaml::Model::Serializable
        # COLR (vector color glyphs).
        attribute :has_colr, Lutaml::Model::Type::Boolean
        attribute :colr_version,            :integer # 0 or 1
        attribute :colr_base_glyph_count,   :integer
        attribute :colr_layer_count,        :integer

        # CPAL (color palette).
        attribute :has_cpal, Lutaml::Model::Type::Boolean
        attribute :cpal_palette_count, :integer
        attribute :cpal_color_count,   :integer

        # SVG-in-OpenType.
        attribute :has_svg, Lutaml::Model::Type::Boolean
        attribute :svg_document_count, :integer

        # CBDT/CBLC (color bitmaps — paired tables).
        attribute :has_cbdt, Lutaml::Model::Type::Boolean
        attribute :has_cblc, Lutaml::Model::Type::Boolean
        # Strike count comes from the paired CBLC locator table.
        attribute :cbdt_strike_count, :integer

        # sbix (Apple color bitmaps).
        attribute :has_sbix, Lutaml::Model::Type::Boolean
        attribute :sbix_strike_count, :integer

        # Derived: ordered list of active color format tags. One of
        # "colr_v0", "colr_v1", "cpal", "svg", "cbdt", "sbix".
        attribute :color_formats, :string, collection: true

        key_value do
          map "has_colr",                to: :has_colr
          map "colr_version",            to: :colr_version
          map "colr_base_glyph_count",   to: :colr_base_glyph_count
          map "colr_layer_count",        to: :colr_layer_count
          map "has_cpal",                to: :has_cpal
          map "cpal_palette_count",      to: :cpal_palette_count
          map "cpal_color_count",        to: :cpal_color_count
          map "has_svg",                 to: :has_svg
          map "svg_document_count",      to: :svg_document_count
          map "has_cbdt",                to: :has_cbdt
          map "has_cblc",                to: :has_cblc
          map "cbdt_strike_count",       to: :cbdt_strike_count
          map "has_sbix",                to: :has_sbix
          map "sbix_strike_count",       to: :sbix_strike_count
          map "color_formats",           to: :color_formats
        end

        # Canonical format tags, kept in spec order.
        FORMAT_COLR_V0 = "colr_v0"
        FORMAT_COLR_V1 = "colr_v1"
        FORMAT_CPAL    = "cpal"
        FORMAT_SVG     = "svg"
        FORMAT_CBDT    = "cbdt"
        FORMAT_SBIX    = "sbix"

        # Derive the canonical color_formats list from individual flags.
        # COLR v1 takes precedence over v0 — a v1 table can serve both.
        #
        # @return [Array<String>]
        def self.derive_formats(has_colr:, colr_version:, has_cpal:,
                                has_svg:, has_cbdt:, has_sbix:)
          [].tap do |arr|
            if has_colr
              arr << (colr_version == 1 ? FORMAT_COLR_V1 : FORMAT_COLR_V0)
            end
            arr << FORMAT_CPAL if has_cpal
            arr << FORMAT_SVG  if has_svg
            arr << FORMAT_CBDT if has_cbdt
            arr << FORMAT_SBIX if has_sbix
          end
        end
      end
    end
  end
end
