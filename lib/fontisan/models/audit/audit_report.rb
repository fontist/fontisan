# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Complete font audit report for a single face.
      #
      # Self-describing: one face per file. Carries source provenance
      # (`source_file`, `source_sha256`, `font_index`, `num_fonts_in_source`)
      # so a consumer reading a single face report knows whether the
      # source was a standalone font or a collection face, and can locate
      # siblings via the source hash.
      #
      # Constructed by Commands::AuditCommand. The model is passive —
      # no font-parsing logic lives here.
      class AuditReport < Lutaml::Model::Serializable
        # Provenance
        attribute :generated_at, :string
        attribute :fontisan_version, :string
        attribute :source_file, :string
        attribute :source_sha256, :string
        attribute :source_format, :string

        # Source layout
        attribute :font_index, :integer
        attribute :num_fonts_in_source, :integer

        # Identity (name table)
        attribute :family_name, :string
        attribute :subfamily_name, :string
        attribute :full_name, :string
        attribute :postscript_name, :string
        attribute :version, :string
        attribute :font_revision, :float

        # Style (OS/2 + head + fvar)
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

        # Aggregations (require UCD)
        attribute :ucd_version, :string
        attribute :blocks, AuditBlock, collection: true
        attribute :unicode_scripts, :string, collection: true
        attribute :opentype_scripts, :string, collection: true
        attribute :features, :string, collection: true

        # Licensing + embedding permissions (nil for Type 1)
        attribute :licensing, Licensing

        # Layout-critical metrics from head/hhea/OS/2/post (nil for Type 1)
        attribute :metrics, Metrics

        # Set when UCD download failed or any non-fatal issue was encountered.
        attribute :warning, :string

        key_value do
          # Provenance
          map "generated_at",       to: :generated_at
          map "fontisan_version",   to: :fontisan_version
          map "source_file",        to: :source_file
          map "source_sha256",      to: :source_sha256
          map "source_format",      to: :source_format

          # Source layout
          map "font_index",          to: :font_index
          map "num_fonts_in_source", to: :num_fonts_in_source

          # Identity
          map "family_name",     to: :family_name
          map "subfamily_name",  to: :subfamily_name
          map "full_name",       to: :full_name
          map "postscript_name", to: :postscript_name
          map "version",         to: :version
          map "font_revision",   to: :font_revision

          # Style
          map "weight_class", to: :weight_class
          map "width_class",  to: :width_class
          map "italic",       to: :italic
          map "bold",         to: :bold
          map "panose",       to: :panose
          map "is_variable",  to: :is_variable
          map "axes",         to: :axes

          # Coverage
          map "total_codepoints", to: :total_codepoints
          map "total_glyphs",     to: :total_glyphs
          map "cmap_subtables",   to: :cmap_subtables
          map "codepoints",       to: :codepoints

          # Aggregations
          map "ucd_version",       to: :ucd_version
          map "blocks",            to: :blocks
          map "unicode_scripts",   to: :unicode_scripts
          map "opentype_scripts",  to: :opentype_scripts
          map "features",          to: :features

          # Licensing
          map "licensing", to: :licensing

          # Metrics
          map "metrics", to: :metrics

          # Warning
          map "warning", to: :warning
        end
      end
    end
  end
end
