# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Namespace for CLDR-derived audit models.
    module Cldr
      autoload :LanguageCoverage, "fontisan/models/cldr/language_coverage"
    end
  end
end
