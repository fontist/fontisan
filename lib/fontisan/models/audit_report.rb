# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Variable-font axis descriptor for the audit report.
    class AuditAxis < Lutaml::Model::Serializable
      attribute :tag, :string
      attribute :min_value, :float
      attribute :default_value, :float
      attribute :max_value, :float
      attribute :name_id, :integer

      json do
        map "tag", to: :tag
        map "min_value", to: :min_value
        map "default_value", to: :default_value
        map "max_value", to: :max_value
        map "name_id", to: :name_id
      end

      yaml do
        map "tag", to: :tag
        map "min_value", to: :min_value
        map "default_value", to: :default_value
        map "max_value", to: :max_value
        map "name_id", to: :name_id
      end
    end

    # Structured font audit report covering identity, style, coverage,
    # and OpenType layout facts. Designed for archival use — each report
    # is self-describing with provenance (generated_at, fontisan_version,
    # source_sha256).
    #
    # The report is a value object: it captures what the font FILE
    # declares, not what any external index says about it.
    class AuditReport < Lutaml::Model::Serializable
      # Provenance
      attribute :generated_at, :string
      attribute :fontisan_version, :string
      attribute :source_file, :string
      attribute :source_sha256, :string
      attribute :source_format, :string
      attribute :font_index, :integer
      attribute :num_fonts_in_source, :integer

      # Identity
      attribute :family_name, :string
      attribute :subfamily_name, :string
      attribute :full_name, :string
      attribute :postscript_name, :string
      attribute :version, :string
      attribute :font_revision, :float

      # Style
      attribute :weight_class, :integer
      attribute :width_class, :integer
      attribute :italic, Lutaml::Model::Type::Boolean
      attribute :bold, Lutaml::Model::Type::Boolean
      attribute :panose, :string
      attribute :is_variable, Lutaml::Model::Type::Boolean
      attribute :axes, AuditAxis, collection: true

      # Coverage
      attribute :total_codepoints, :integer
      attribute :total_glyphs, :integer
      attribute :cmap_subtables, :integer, collection: true
      attribute :codepoints, :string, collection: true

      # OpenType layout
      attribute :opentype_scripts, :string, collection: true
      attribute :features, :string, collection: true

      json do
        map "generated_at", to: :generated_at
        map "fontisan_version", to: :fontisan_version
        map "source_file", to: :source_file
        map "source_sha256", to: :source_sha256
        map "source_format", to: :source_format
        map "font_index", to: :font_index
        map "num_fonts_in_source", to: :num_fonts_in_source

        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "full_name", to: :full_name
        map "postscript_name", to: :postscript_name
        map "version", to: :version
        map "font_revision", to: :font_revision

        map "weight_class", to: :weight_class
        map "width_class", to: :width_class
        map "italic", to: :italic
        map "bold", to: :bold
        map "panose", to: :panose
        map "is_variable", to: :is_variable
        map "axes", to: :axes

        map "total_codepoints", to: :total_codepoints
        map "total_glyphs", to: :total_glyphs
        map "cmap_subtables", to: :cmap_subtables
        map "codepoints", to: :codepoints

        map "opentype_scripts", to: :opentype_scripts
        map "features", to: :features
      end

      yaml do
        map "generated_at", to: :generated_at
        map "fontisan_version", to: :fontisan_version
        map "source_file", to: :source_file
        map "source_sha256", to: :source_sha256
        map "source_format", to: :source_format
        map "font_index", to: :font_index
        map "num_fonts_in_source", to: :num_fonts_in_source

        map "family_name", to: :family_name
        map "subfamily_name", to: :subfamily_name
        map "full_name", to: :full_name
        map "postscript_name", to: :postscript_name
        map "version", to: :version
        map "font_revision", to: :font_revision

        map "weight_class", to: :weight_class
        map "width_class", to: :width_class
        map "italic", to: :italic
        map "bold", to: :bold
        map "panose", to: :panose
        map "is_variable", to: :is_variable
        map "axes", to: :axes

        map "total_codepoints", to: :total_codepoints
        map "total_glyphs", to: :total_glyphs
        map "cmap_subtables", to: :cmap_subtables
        map "codepoints", to: :codepoints

        map "opentype_scripts", to: :opentype_scripts
        map "features", to: :features
      end
    end
  end
end
