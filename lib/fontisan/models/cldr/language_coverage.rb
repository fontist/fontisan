# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Cldr
      # Per-language coverage for one face against a CLDR exemplar set.
      #
      # `coverage_ratio` is in [0.0, 1.0] rounded to 4 decimal places;
      # `fully_supported` is true only when every required codepoint
      # (total > 0) is covered. A language with total == 0 (empty exemplar
      # set in the index) is reported as ratio 0.0, fully_supported false.
      class LanguageCoverage < Lutaml::Model::Serializable
        attribute :language,        :string
        attribute :covered,         :integer
        attribute :total,           :integer
        attribute :coverage_ratio,  :float
        attribute :fully_supported, Lutaml::Model::Type::Boolean

        key_value do
          map "language",        to: :language
          map "covered",         to: :covered
          map "total",           to: :total
          map "coverage_ratio",  to: :coverage_ratio
          map "fully_supported", to: :fully_supported
        end
      end
    end
  end
end
