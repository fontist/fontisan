# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One scalar field that differs between two AuditReports.
      #
      # `field` is the dotted attribute name (e.g. "weight_class").
      # `left`/`right` are stringified values: nil → "", String → itself,
      # anything else → its YAML form. Comparing the YAML form of nested
      # models is intentionally avoided here — those diffs surface as
      # structural add/remove lists on AuditDiff itself.
      class FieldChange < Lutaml::Model::Serializable
        attribute :field, :string
        attribute :left,  :string
        attribute :right, :string

        key_value do
          map "field", to: :field
          map "left",  to: :left
          map "right", to: :right
        end
      end
    end
  end
end
