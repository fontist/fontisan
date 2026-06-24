# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One row in a LibrarySummary's script-coverage matrix.
      #
      # Lists every face (by postscript_name) whose cmap covers at least
      # one codepoint assigned to a Unicode script. Lets a librarian
      # answer "which fonts cover Cyrillic?" without re-auditing.
      class ScriptCoverageRow < Lutaml::Model::Serializable
        attribute :script, :string
        attribute :face_count, :integer
        attribute :faces, :string, collection: true

        key_value do
          map "script", to: :script
          map "face_count", to: :face_count
          map "faces", to: :faces
        end
      end
    end
  end
end
