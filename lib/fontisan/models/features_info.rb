# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Represents a single feature record
    class FeatureRecord < Lutaml::Model::Serializable
      attribute :tag, :string
      attribute :description, :string

      json do
        map "tag", to: :tag
        map "description", to: :description
      end

      yaml do
        map "tag", to: :tag
        map "description", to: :description
      end
    end

    # Represents features information from GSUB/GPOS tables
    class FeaturesInfo < Lutaml::Model::Serializable
      attribute :script, :string
      attribute :feature_count, :integer
      attribute :features, FeatureRecord, collection: true

      json do
        map "script", to: :script
        map "feature_count", to: :feature_count
        map "features", to: :features
      end

      yaml do
        map "script", to: :script
        map "feature_count", to: :feature_count
        map "features", to: :features
      end
    end
  end
end
