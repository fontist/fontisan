# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Audit
      # One fvar axis descriptor on an AuditReport.
      #
      # `min_value` / `default_value` / `max_value` are used (rather than
      # `min` / `default` / `max`) to avoid colliding with Ruby's built-in
      # `default` method on classes.
      class AuditAxis < Lutaml::Model::Serializable
        attribute :tag, :string
        attribute :min_value, :float
        attribute :default_value, :float
        attribute :max_value, :float
        attribute :name, :string

        key_value do
          map "tag",           to: :tag
          map "min_value",     to: :min_value
          map "default_value", to: :default_value
          map "max_value",     to: :max_value
          map "name",          to: :name
        end
      end
    end
  end
end
