# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One Unicode block coverage row on an AuditReport.
      class AuditBlock < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :first_cp, :integer
        attribute :last_cp, :integer
        attribute :range, :string
        attribute :total, :integer
        attribute :covered, :integer
        attribute :fill_ratio, :float
        attribute :complete, Lutaml::Model::Type::Boolean

        key_value do
          map "name",       to: :name
          map "first_cp",   to: :first_cp
          map "last_cp",    to: :last_cp
          map "range",      to: :range
          map "total",      to: :total
          map "covered",    to: :covered
          map "fill_ratio", to: :fill_ratio
          map "complete",   to: :complete
        end
      end
    end
  end
end
