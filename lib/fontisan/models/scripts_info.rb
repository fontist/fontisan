# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Represents a single script record
    class ScriptRecord < Lutaml::Model::Serializable
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

    # Represents scripts information from GSUB/GPOS tables
    class ScriptsInfo < Lutaml::Model::Serializable
      attribute :script_count, :integer
      attribute :scripts, ScriptRecord, collection: true

      json do
        map "script_count", to: :script_count
        map "scripts", to: :scripts
      end

      yaml do
        map "script_count", to: :script_count
        map "scripts", to: :scripts
      end
    end
  end
end
