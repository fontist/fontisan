# frozen_string_literal: true

require "lutaml/model"
require_relative "features_info"

module Fontisan
  module Models
    # Represents features information for all scripts from GSUB/GPOS tables
    class AllScriptsFeaturesInfo < Lutaml::Model::Serializable
      attribute :scripts_features, FeaturesInfo, collection: true

      json do
        map "scripts_features", to: :scripts_features
      end

      yaml do
        map "scripts_features", to: :scripts_features
      end
    end
  end
end
