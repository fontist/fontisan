# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ucd
      # Root <ucd> element of the UCDXML flat file.
      #
      # The flat UCDXML file has the structure:
      #
      #   <ucd>
      #     <description>...</description>
      #     <last_revision date="2025-..." version="17.0.0" />
      #     <char cp="0000" .../>
      #     <char cp="0001" .../>
      #     ...
      #     <char first-cp="3400" last-cp="4DBF" .../>
      #     ...
      #   </ucd>
      #
      # The flat variant merges all per-category UCD files (Blocks.txt,
      # Scripts.txt, UnicodeData.txt, etc.) into one stream of <char>
      # elements. Roughly 340,000 entries for Unicode 17.0.0.
      class Ucd < Lutaml::Model::Serializable
        attribute :last_revision, :string
        attribute :chars, UcdChar, collection: true

        xml do
          element "ucd"

          map_element "last_revision", to: :last_revision
          map_element "char", to: :chars
        end
      end
    end
  end
end
