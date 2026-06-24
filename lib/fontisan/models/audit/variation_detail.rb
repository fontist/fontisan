# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Variable-font detail for one face.
      #
      # Bundles everything fvar-derived (axes + named instances) with the
      # presence flags for every variation side-table (avar/cvar/HVAR/VVAR/
      # MVAR/gvar). Replaces the previous flat `axes` + `is_variable` pair
      # on AuditReport for MECE cleanliness — a face is variable iff this
      # object is non-nil.
      #
      # `axes` reuses the existing AuditAxis shape; `named_instances` is a
      # parallel NamedInstance collection. The has_* booleans are presence
      # checks only — they don't validate the table contents.
      class VariationDetail < Lutaml::Model::Serializable
        attribute :axes,            AuditAxis,      collection: true
        attribute :named_instances, NamedInstance,  collection: true

        # Variation side-table presence flags.
        attribute :has_avar, Lutaml::Model::Type::Boolean # axis variation
        attribute :has_cvar, Lutaml::Model::Type::Boolean # CVT variation
        attribute :has_hvar, Lutaml::Model::Type::Boolean # horizontal metrics
        attribute :has_vvar, Lutaml::Model::Type::Boolean # vertical metrics
        attribute :has_mvar, Lutaml::Model::Type::Boolean # metrics variation
        attribute :has_gvar, Lutaml::Model::Type::Boolean # glyph variation (TT)

        key_value do
          map "axes",            to: :axes
          map "named_instances", to: :named_instances
          map "has_avar", to: :has_avar
          map "has_cvar", to: :has_cvar
          map "has_hvar", to: :has_hvar
          map "has_vvar", to: :has_vvar
          map "has_mvar", to: :has_mvar
          map "has_gvar", to: :has_gvar
        end
      end
    end
  end
end
