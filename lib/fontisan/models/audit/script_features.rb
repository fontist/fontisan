# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Per-script breakdown of OpenType features.
      #
      # Pairs a script tag (e.g. "latn", "kana ") with the GSUB features
      # and GPOS features that apply to it. The two collections are
      # kept separate because substitution and positioning have different
      # semantics — consumers answering "does this font support kerning
      # for Latin?" want to look at GPOS only.
      class ScriptFeatures < Lutaml::Model::Serializable
        attribute :script,         :string
        attribute :gsub_features,  :string, collection: true
        attribute :gpos_features,  :string, collection: true

        key_value do
          map "script",        to: :script
          map "gsub_features", to: :gsub_features
          map "gpos_features", to: :gpos_features
        end
      end
    end
  end
end
