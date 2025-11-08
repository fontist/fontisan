# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # AxisInfo model represents a single variation axis in a variable font
    #
    # Each axis defines a design dimension along which the font can vary,
    # such as weight (wght), width (wdth), italic (ital), or slant (slnt).
    class AxisInfo < Lutaml::Model::Serializable
      attribute :tag, :string
      attribute :name, :string
      attribute :min_value, :float
      attribute :default_value, :float
      attribute :max_value, :float

      json do
        map "tag", to: :tag
        map "name", to: :name
        map "min_value", to: :min_value
        map "default_value", to: :default_value
        map "max_value", to: :max_value
      end

      yaml do
        map "tag", to: :tag
        map "name", to: :name
        map "min_value", to: :min_value
        map "default_value", to: :default_value
        map "max_value", to: :max_value
      end
    end

    # InstanceInfo model represents a named instance in a variable font
    #
    # Each instance defines a predefined combination of axis values,
    # representing a named style/weight/width combination.
    class InstanceInfo < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :coordinates, :float, collection: true

      json do
        map "name", to: :name
        map "coordinates", to: :coordinates
      end

      yaml do
        map "name", to: :name
        map "coordinates", to: :coordinates
      end
    end

    # VariableFontInfo model represents comprehensive variable font metadata
    #
    # This model provides information about variation axes and named instances
    # for variable fonts (OpenType Font Variations).
    class VariableFontInfo < Lutaml::Model::Serializable
      attribute :is_variable, Lutaml::Model::Type::Boolean
      attribute :axis_count, :integer
      attribute :instance_count, :integer
      attribute :axes, AxisInfo, collection: true
      attribute :instances, InstanceInfo, collection: true

      json do
        map "is_variable", to: :is_variable
        map "axis_count", to: :axis_count
        map "instance_count", to: :instance_count
        map "axes", to: :axes
        map "instances", to: :instances
      end

      yaml do
        map "is_variable", to: :is_variable
        map "axis_count", to: :axis_count
        map "instance_count", to: :instance_count
        map "axes", to: :axes
        map "instances", to: :instances
      end
    end
  end
end
