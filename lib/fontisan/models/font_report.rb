# frozen_string_literal: true

require_relative "validation_report"
require "lutaml/model"

module Fontisan
  module Models
    # FontReport wraps a single font's validation report with collection context
    #
    # Used within CollectionValidationReport to associate validation results
    # with a specific font index and name in the collection.
    class FontReport < Lutaml::Model::Serializable
      attribute :font_index, :integer
      attribute :font_name, :string
      attribute :report, ValidationReport

      key_value do
        map "font_index", to: :font_index
        map "font_name", to: :font_name
        map "report", to: :report
      end
    end
  end
end
