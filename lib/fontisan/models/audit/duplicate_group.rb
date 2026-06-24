# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # Group of files that share an identical `source_sha256`.
      #
      # Detecting duplicate byte-identical files (regardless of filename)
      # is the cheapest form of library hygiene: same bytes = same font.
      class DuplicateGroup < Lutaml::Model::Serializable
        attribute :source_sha256, :string
        attribute :files, :string, collection: true

        key_value do
          map "source_sha256", to: :source_sha256
          map "files", to: :files
        end
      end
    end
  end
end
