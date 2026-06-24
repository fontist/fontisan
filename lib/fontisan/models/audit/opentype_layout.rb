# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Structured OpenType layout summary for one face.
      #
      # Replaces the previous flat `opentype_scripts` + `features` pair
      # on AuditReport for MECE cleanliness. Carries:
      #
      # - `scripts`: union of GSUB + GPOS script tags (sorted, unique).
      # - `features`: union of GSUB + GPOS feature tags across every
      #   script (sorted, unique).
      # - `by_script`: per-script breakdown preserving the
      #   "feature X is for script Y" relationship that the flat arrays
      #   discarded.
      # - `has_gsub` / `has_gpos`: presence flags so consumers can tell
      #   "font has no layout" from "font has GSUB but no GPOS".
      #
      # nil for Type 1 fonts (no SFNT table structure).
      class OpenTypeLayout < Lutaml::Model::Serializable
        attribute :scripts,   :string,         collection: true
        attribute :features,  :string,         collection: true
        attribute :by_script, ScriptFeatures,  collection: true
        attribute :has_gsub,  Lutaml::Model::Type::Boolean
        attribute :has_gpos,  Lutaml::Model::Type::Boolean

        key_value do
          map "scripts",   to: :scripts
          map "features",  to: :features
          map "by_script", to: :by_script
          map "has_gsub",  to: :has_gsub
          map "has_gpos",  to: :has_gpos
        end
      end
    end
  end
end
